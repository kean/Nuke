// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Combine // For `ObservableObject`
import CoreGraphics
import Foundation
import Nuke

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// Plays an animated image: decodes its frames off the main thread, keeps a
/// bounded number of them in memory, and hands them to a view on time.
///
/// ```swift
/// let player = AnimatedImagePlayer(source: source)
/// player.onFrame = { imageView.image = $0 }
/// player.play()
/// ```
///
/// ``AnimatedImageView`` and ``AnimatedImage`` create a player for you; create
/// one yourself to drive playback – or read ``diagnostics`` – from your own
/// view.
///
/// The player is an `ObservableObject` that publishes the playback state
/// changing (``isPlaying`` and ``isFinished``) and deliberately not the
/// animation running: the frames go to the view directly, and
/// ``currentFrameIndex`` and ``completedLoopCount`` advance without a signal.
///
/// See <doc:AnimatedImages>.
@MainActor
public final class AnimatedImagePlayer: ObservableObject {
    /// The image being played.
    public let source: AnimatedImageSource

    /// The options the player was created with.
    public let options: Options

    /// The frame currently on screen.
    public private(set) var currentFrameIndex = 0

    /// The image of the current frame, or `nil` until the first frame is
    /// decoded.
    public private(set) var image: PlatformImage?

    /// Whether the clock is running.
    @Published public private(set) var isPlaying = false

    /// `true` when the animation has played the number of loops it was asked to
    /// and stopped on its last frame.
    @Published public private(set) var isFinished = false

    /// The number of loops completed since the player was created.
    public private(set) var completedLoopCount = 0

    /// Called every time a new frame is ready to be displayed.
    ///
    /// The views display the frames of a player they are given through a
    /// channel of their own, so handing one of them a player doesn't replace
    /// this handler.
    public var onFrame: ((PlatformImage) -> Void)?

    /// Called with the number of completed loops every time the animation
    /// wraps around.
    public var onLoop: ((Int) -> Void)?

    /// Called when the animation stops because it has played all of its loops.
    public var onFinish: (() -> Void)?

    /// The handler the views display the frames through, separate from
    /// ``onFrame`` so that a view never replaces the handler its owner set.
    var onFrameForDisplay: ((PlatformImage) -> Void)?

    /// The decoded frames of this animation at this size, shared with every
    /// other player showing it.
    let store: AnimatedImageFrameStore

    private let clock: any AnimatedImageClock
    private let pool: AnimatedImageFramePool
    private let power: AnimatedImagePowerMonitor

    /// The number of frames the player is willing to hold, whatever the pool
    /// has to spare: ``Options/maxBufferSize`` in frames, at what a frame costs
    /// decoded at the size it is decoded at, or every frame when the player
    /// has no ceiling of its own.
    private var affordableFrameCount: Int {
        guard let maxBufferSize = options.maxBufferSize, store.bytesPerFrame > 0 else { return source.frameCount }
        return maxBufferSize / store.bytesPerFrame
    }

    private var elapsed: TimeInterval = 0
    private var displayedFrameIndex: Int?

    /// `true` while the frame after the current one is due and still on its
    /// way from the decoder.
    private var isWaitingForNextFrame = false

    private var counters = Counters()

    /// Creates a player for the given image.
    public convenience init(source: AnimatedImageSource, options: Options = Options()) {
        self.init(source: source, options: options, clock: makeAnimatedImageClock())
    }

    init(
        source: AnimatedImageSource,
        options: Options,
        clock: any AnimatedImageClock,
        pool: AnimatedImageFramePool = .shared,
        power: AnimatedImagePowerMonitor = .shared,
        decoder: (any AnimatedImageFrameDecoding)? = nil
    ) {
        self.source = source
        self.options = options
        self.clock = clock
        self.pool = pool
        self.power = power
        self.store = pool.store(
            for: source,
            maxPixelSize: options.maxPixelSize,
            transform: options.frameTransform,
            decoder: decoder
        )
        // Nobody is watching until something calls `play()`, so the player asks
        // for the first frames only. It does ask for those: an animation that
        // is never played still shows its first frame.
        self.keepsFullBuffer = false
        // Fall in behind whatever is already playing this animation, so that
        // the copies of one sticker share one window of frames. Read before
        // joining, so that the player never falls in behind itself.
        self.currentFrameIndex = options.isSynchronizationEnabled ? store.leadingIndex() ?? 0 : 0

        updateClockRate()
        clock.onTick = { [weak self] in self?.tick($0) }
        power.add(self)
        // Last, because joining is what starts the decoding and what hands the
        // store its first share of the pool.
        store.add(self)
        pool.rebalance()
    }

    deinit {
        // A `deinit` isn't on the main actor, so the pool is asked to divide
        // the budget on the next turn, which also sweeps this player out of
        // the store. The clock goes with the player and stops itself.
        pool.setNeedsRebalance()
    }

    // MARK: Playback

    /// Starts or resumes playback.
    ///
    /// Does nothing if the animation has already finished; call ``restart()``
    /// to play it from the beginning, or ``seek(toFrame:)`` to pick up
    /// somewhere else.
    public func play() {
        guard !isPlaying, !isFinished else { return }
        isPlaying = true
        keepsFullBuffer = true
        clock.isPaused = false
    }

    /// Pauses playback on the current frame.
    public func pause() {
        guard isPlaying else { return }
        isPlaying = false
        clock.isPaused = true
    }

    /// Returns to the first frame and starts playing.
    public func restart() {
        completedLoopCount = 0
        seek(toFrame: 0)
        play()
    }

    /// Displays the frame at the given index.
    ///
    /// The index is clamped to the number of frames in the animation. The
    /// frames around the destination start decoding immediately, and the frame
    /// itself appears as soon as it is ready. A player that has played all of
    /// its loops can be seeked and played again.
    public func seek(toFrame index: Int) {
        let index = min(max(0, index), source.frameCount - 1)
        // Assigned on every seek, whether or not it changes: a `@Published`
        // property publishes on assignment, and this is what publishes the
        // move to observers. `currentFrameIndex` can't do it itself without
        // putting the SwiftUI graph on the frame clock.
        isFinished = false
        currentFrameIndex = index
        elapsed = 0
        isWaitingForNextFrame = false
        // The frame being decoded is for somewhere the playhead has just left:
        // nobody is waiting for it any more.
        store.didUpdateWindow(of: self, isSeeking: true)
        display(frameAt: index)
    }

    /// Picks up where another player of the same animation left off.
    ///
    /// ``AnimatedImageView`` builds a player of its own whenever it outgrows
    /// the size its frames were decoded for; without this the animation would
    /// start over every time the view was resized.
    func resume(from player: AnimatedImagePlayer) {
        completedLoopCount = player.completedLoopCount
        seek(toFrame: player.currentFrameIndex)
        // After the seek, which clears it: an animation that has played all of
        // its loops stays finished at its new size.
        isFinished = player.isFinished
    }

    // MARK: Memory

    /// Whether the player keeps a full window of decoded frames. `true` by
    /// default.
    ///
    /// ``AnimatedImageView`` sets it to `false` for a player nobody is
    /// watching – a view that has scrolled off screen – which keeps the frame
    /// on display and the one after it and gives the rest of the window back.
    /// ``play()`` sets it back to `true`. Playback paused in place keeps its
    /// frames, so that resuming doesn't stall.
    var keepsFullBuffer = true {
        didSet {
            guard keepsFullBuffer != oldValue else { return }
            // The new share is what drops the frames that no longer fit and
            // starts decoding into the room that opened up.
            pool.rebalance()
        }
    }

    // MARK: Buffering

    /// The number of frames the player is allowed to hold: what it wants, or
    /// the share of the animation the pool has left it, whichever is smaller –
    /// and no more than the read-ahead unless that share is the whole animation.
    var bufferCapacity: Int {
        bufferCapacity(windowLength: store.windowLength)
    }

    /// The capacity for a window length the store has already computed.
    ///
    /// ``AnimatedImageFrameStore/windowLength`` walks the members, so a store
    /// works out the length its members share once and hands it to each of
    /// them: a member reading it for itself makes moving one playhead cost the
    /// square of the number of players drawing from the animation.
    func bufferCapacity(windowLength: Int) -> Int {
        let granted = min(windowLength, wantedFrameCount)
        let capacity = granted >= source.frameCount ? granted : min(granted, Self.readAheadFrameCount + 1)
        return max(Self.idleFrameCount, capacity)
    }

    /// The number of frames the player would hold if the pool had the memory to
    /// spare: every frame, unless ``Options/maxBufferSize`` doesn't cover them
    /// all, in which case the frame on screen and the read-ahead – and only
    /// ``idleFrameCount`` while nobody is watching or the system is short of
    /// memory.
    var wantedFrameCount: Int {
        guard keepsFullBuffer, !pool.isUnderMemoryPressure else { return Self.idleFrameCount }
        let affordable = affordableFrameCount
        guard affordable < source.frameCount else { return source.frameCount }
        return max(Self.idleFrameCount, min(Self.readAheadFrameCount + 1, affordable))
    }

    /// The range of frame indexes the player is claiming, which may run past
    /// the last frame and wrap around.
    var window: Range<Int> {
        currentFrameIndex..<(currentFrameIndex + bufferCapacity)
    }

    /// `true` when the player is claiming the frame at the given index.
    func wants(_ index: Int) -> Bool {
        (index - currentFrameIndex + source.frameCount) % source.frameCount < bufferCapacity
    }

    /// What a player holds while nobody is watching, and the floor for every
    /// player: with one frame, the next could only start decoding after the
    /// current one was dropped.
    static let idleFrameCount = 2

    /// The number of frames decoded ahead of the one on screen while the
    /// animation doesn't fit in memory.
    ///
    /// A window that slides re-decodes every frame each loop however long it
    /// is, so past what absorbs a slow decode or a busy core, more of it buys
    /// nothing. Two is enough for that, and the memory beyond it is left to
    /// the animations that do fit.
    static let readAheadFrameCount = 2

    /// The largest gap between two clock ticks the player counts as playback,
    /// in seconds.
    ///
    /// A clock that was starved – the app was in the background – reports the
    /// whole gap in one tick. The player moves on by one frame either way;
    /// what the cap keeps honest is the playback time it reports.
    static let maxTimeStep: TimeInterval = 1

    /// Called by the store with every frame the player was waiting for.
    func storeDidDecodeFrame(at index: Int, duration: TimeInterval) {
        counters.decodedFrameCount += 1
        counters.lastDecodeDuration = duration
        counters.totalDecodeDuration += duration
        counters.maxDecodeDuration = max(counters.maxDecodeDuration, duration)
        frameDidDecode(at: index)
    }

    // MARK: Diagnostics

    /// A snapshot of what the player is doing.
    public var diagnostics: Diagnostics {
        var diagnostics = Diagnostics()
        diagnostics.frameCount = source.frameCount
        diagnostics.currentFrameIndex = currentFrameIndex
        diagnostics.completedLoopCount = completedLoopCount
        diagnostics.bufferedFrameCount = store.decodedFrameCount(in: window)
        diagnostics.bufferCapacity = bufferCapacity
        diagnostics.bufferedByteCount = store.byteCount(in: window)
        diagnostics.bufferByteLimit = bufferCapacity * store.bytesPerFrame
        diagnostics.sharingPlayerCount = store.memberCount
        diagnostics.decodedFrameCount = counters.decodedFrameCount
        diagnostics.lastDecodeDuration = counters.lastDecodeDuration
        diagnostics.averageDecodeDuration = counters.decodedFrameCount > 0
            ? counters.totalDecodeDuration / Double(counters.decodedFrameCount) : 0
        diagnostics.maxDecodeDuration = counters.maxDecodeDuration
        diagnostics.displayedFrameCount = counters.displayedFrameCount
        diagnostics.bufferMissCount = counters.bufferMissCount
        diagnostics.playbackTime = counters.playbackTime
        return diagnostics
    }

    /// Returns `true` if the frame at the given index is decoded and in memory.
    ///
    /// Together with ``Diagnostics/bufferCapacity`` it is enough to draw what
    /// the buffer is holding, which is what the demo app does.
    public func isFrameBuffered(_ index: Int) -> Bool {
        store.frame(at: index) != nil
    }

    /// Waits until the window is full or until there is nothing left to decode.
    ///
    /// For the tests, which need a point where the player is settled rather
    /// than a sleep long enough to probably work.
    func waitUntilFull() async {
        while let task = store.currentDecode {
            await task.value
        }
    }

    // MARK: Private

    private func tick(_ delta: TimeInterval) {
        guard isPlaying, !isFinished else { return }

        // Time counts only against a frame that is on screen. Playback usually
        // starts before the first frame is decoded, and a seek lands on a
        // frame that mostly isn't yet; the frame on its way gets its whole
        // delay once it is shown. A frame the decoder refuses stops being
        // pending, so the wait always ends.
        guard displayedFrameIndex == currentFrameIndex || !store.isPending(currentFrameIndex) else {
            return
        }

        let step = min(delta, Self.maxTimeStep) * options.playbackRate
        guard step > 0 else { return }
        counters.playbackTime += step
        elapsed += step

        var advanced = false
        while elapsed >= source.delays[currentFrameIndex] {
            guard let next = nextFrameIndex else {
                finish()
                break
            }
            guard store.frame(at: next) != nil || !store.isPending(next) else {
                // The frame is late. The one on screen stays until it arrives –
                // no frame is ever skipped, the way a browser plays – and the
                // animation stretches by however long that takes.
                if !isWaitingForNextFrame {
                    isWaitingForNextFrame = true
                    counters.bufferMissCount += 1
                    // Asked for rather than assumed: a player waiting on a
                    // frame nobody is producing would wait forever.
                    store.didUpdateWindow(of: self, isSeeking: false)
                }
                break
            }
            let remainder = elapsed - source.delays[currentFrameIndex]
            advance(to: next)
            // What is left of a tick that came on time carries over, so that a
            // 70 ms frame on a 50 ms clock averages 70 ms and not 100. What is
            // left of a tick that came late doesn't: the frame just shown gets
            // its whole delay from now rather than being cut short to catch
            // up, so a stall stretches the animation instead of jumping it.
            // The carry-over can only reach a frame shorter than a tick, which
            // the display couldn't have shown for longer anyway.
            elapsed = min(remainder, clock.period * options.playbackRate)
            advanced = true
        }
        guard advanced else { return }

        store.didUpdateWindow(of: self, isSeeking: false)
        display(frameAt: currentFrameIndex)
    }

    /// The frame after the current one, or `nil` when the current frame is
    /// the last one of the last loop.
    private var nextFrameIndex: Int? {
        let next = currentFrameIndex + 1
        guard next >= source.frameCount else { return next }
        if let limit = repeatLimit, completedLoopCount + 1 >= limit {
            return nil
        }
        return 0
    }

    /// Moves the playhead to the given frame, counting a loop when it wraps.
    private func advance(to index: Int) {
        if index == 0 {
            completedLoopCount += 1
            onLoop?(completedLoopCount)
        }
        currentFrameIndex = index
        isWaitingForNextFrame = false
    }

    /// Stops on the last frame of the last loop.
    private func finish() {
        completedLoopCount += 1
        onLoop?(completedLoopCount)
        isFinished = true
        isPlaying = false
        clock.isPaused = true
        onFinish?()
    }

    /// The number of loops to play, or `nil` for "forever".
    private var repeatLimit: Int? {
        switch options.repeatCount {
        case .image: source.loopCount > 0 ? source.loopCount : nil
        case .infinite: nil
        case .finite(let count): max(1, count)
        }
    }

    private func display(frameAt index: Int) {
        guard displayedFrameIndex != index else {
            return
        }
        guard let cgImage = store.frame(at: index) else {
            // The frame a seek landed on before it is decoded, or one the
            // decoder refused. The previous frame stays on screen, and this
            // one is displayed by `frameDidDecode(at:)` when it arrives.
            counters.bufferMissCount += 1
            return
        }
        displayedFrameIndex = index
        counters.displayedFrameCount += 1
        let image = makeImage(cgImage)
        self.image = image
        onFrameForDisplay?(image)
        onFrame?(image)
    }

    private func frameDidDecode(at index: Int) {
        guard displayedFrameIndex != index else { return }
        if index == currentFrameIndex {
            // The frame the playhead is on: the first one, or the one a seek
            // landed on. Its delay starts when it is shown.
            return display(frameAt: index)
        }
        // The frame the playhead has been waiting on is shown now, for its
        // whole delay from now. Any other frame – read-ahead, or one a seek
        // left behind – is for the clock to reach.
        guard isPlaying, isWaitingForNextFrame, index == nextFrameIndex else { return }
        advance(to: index)
        elapsed = 0
        store.didUpdateWindow(of: self, isSeeking: false)
        display(frameAt: index)
    }

    private func makeImage(_ cgImage: CGImage) -> PlatformImage {
#if canImport(UIKit)
        UIImage(cgImage: cgImage, scale: options.scale, orientation: .up)
#else
        // `NSImage` has no scale: it has a size in points and a bitmap in
        // pixels. Built at the pixel size it draws too large wherever nothing
        // rescales it, `imageScaling` of `.scaleNone` being the case.
        let scale = options.scale > 0 ? options.scale : 1
        return NSImage(cgImage: cgImage, size: NSSize(
            width: CGFloat(cgImage.width) / scale,
            height: CGFloat(cgImage.height) / scale
        ))
#endif
    }

    /// Tells the clock the rate to run at, which the power state can change
    /// while the animation is playing.
    func updateClockRate() {
        let isThrottling = options.isPowerThrottlingEnabled && power.isThrottling
        clock.preferredFrameRate = AnimatedImagePlayer.preferredFrameRate(for: source, options: options, isThrottling: isThrottling)
    }

    /// The rate to run the clock at, or `0` to let it use its own.
    ///
    /// Twice the fastest frame in the animation guarantees a tick to show
    /// every frame on: at exactly one tick per frame the two rates beat against
    /// each other and every other frame is held a tick too long. Above 60
    /// ticks a second the hint is dropped: a clock asked for more than the
    /// display gives runs at the display's rate anyway, and the timer clock
    /// schedules itself at exactly this rate.
    ///
    /// While the system is throttling, the ceiling is 30 instead and the rate
    /// is clamped to it rather than dropped: a fast animation is deliberately
    /// run on a clock too coarse for it, which stretches its frames by up to a
    /// tick and skips none. See ``Options/isPowerThrottlingEnabled``.
    private static func preferredFrameRate(for source: AnimatedImageSource, options: Options, isThrottling: Bool) -> Double {
        let ceiling: Double = isThrottling ? 30 : 60
        guard let shortest = source.delays.min(), shortest > 0 else {
            return isThrottling ? ceiling : 0
        }
        let ticksPerSecond = (1 / shortest) * max(options.playbackRate, 1) * 2
        if ticksPerSecond <= ceiling {
            return ticksPerSecond
        }
        return isThrottling ? ceiling : 0
    }

    /// What the player counts as it plays, for ``diagnostics``.
    private struct Counters {
        var displayedFrameCount = 0
        var bufferMissCount = 0
        var playbackTime: TimeInterval = 0
        var decodedFrameCount = 0
        var lastDecodeDuration: TimeInterval = 0
        var totalDecodeDuration: TimeInterval = 0
        var maxDecodeDuration: TimeInterval = 0
    }
}

extension AnimatedImagePlayer {
    /// The options that change how an animation is played and how much memory
    /// it is allowed to use.
    public struct Options: Sendable {
        /// How many times to play the animation. ``RepeatCount/image`` by
        /// default, which honors what the file asks for.
        public var repeatCount: RepeatCount = .image

        /// The speed multiplier. `1` by default.
        public var playbackRate: Double = 1

        /// The most memory this player's decoded frames may occupy, in bytes.
        /// `nil` – no ceiling of the player's own – by default.
        ///
        /// An animation whose frames all fit in memory is decoded once and
        /// replayed from it; one that doesn't is decoded as it plays, a few
        /// frames ahead of the one on screen. Whether it fits is up to
        /// ``AnimatedImageFramePool``: alone, an animation may take the whole
        /// pool, and beside others it is held whole if the pool can fit it
        /// beside them. Set a ceiling here to hold one animation to less than
        /// that. What is measured is what the frames cost decoded – the canvas
        /// at four bytes a pixel, less whatever ``maxPixelSize`` scales away –
        /// not the size of the file.
        public var maxBufferSize: Int?

        /// The longest side, in pixels, the decoded frames may have. `nil` –
        /// no downsampling – by default.
        ///
        /// Set it to the size of the view in pixels to play an animation much
        /// larger than the space it is displayed in: the frames are scaled as
        /// they are decoded, which cuts the memory each one costs by the
        /// square of the scale.
        public var maxPixelSize: CGFloat?

        /// The scale of the images the player produces. `1` by default.
        public var scale: CGFloat = 1

        /// A transformation applied to every frame as it is decoded – a tint,
        /// a rounded corner, a filter. `nil` – the frames as they are decoded
        /// – by default.
        ///
        /// It runs on the decoder rather than the main actor, and the frames
        /// it produces are the ones every player asking for the same
        /// ``AnimatedImageFrameTransform/identifier`` shares.
        public var frameTransform: AnimatedImageFrameTransform?

        /// Whether the player starts on the frame the other players of the
        /// same animation are showing, rather than on the first one. `true` by
        /// default.
        ///
        /// When the playheads agree, one window of frames covers every copy of
        /// an animation on screen. It is also what a browser does: every `img`
        /// element showing one animation plays in lockstep. Set it to `false`
        /// for a player that should always begin at the beginning – an
        /// animation played once as a transition, say.
        public var isSynchronizationEnabled = true

        /// Whether the clock slows down while the system is asking for less
        /// work. `true` by default.
        ///
        /// In Low Power Mode, or on a device hot enough that the system is
        /// already throttling it, the player asks its clock for at most 30
        /// ticks a second instead of the two per frame it normally would,
        /// which halves the wakeups an animation costs on battery. It is what
        /// WebKit does for the same two reasons. Nothing is skipped: an
        /// animation faster than the clock has its frames stretched by up to a
        /// tick each, so it plays a little slower while the throttling lasts.
        /// Set it to `false` for an animation that has to keep its timing
        /// whatever the state of the device.
        public var isPowerThrottlingEnabled = true

        public init() {}
    }

    /// How many times an animation should play.
    @frozen public enum RepeatCount: Hashable, Sendable {
        /// Whatever the image asks for, which is almost always forever.
        case image
        /// Play forever, whatever the image asks for.
        case infinite
        /// Play a set number of times, then stop on the last frame.
        case finite(Int)
    }

    /// What the player is doing, for logging, tests, and the diagnostics
    /// overlay in the demo app.
    public struct Diagnostics: Sendable {
        /// Creates an empty snapshot.
        public init() {}

        /// The number of frames in the animation.
        public var frameCount = 0
        /// The frame currently on screen.
        public var currentFrameIndex = 0
        /// The number of completed loops.
        public var completedLoopCount = 0

        /// The number of decoded frames held in memory.
        public var bufferedFrameCount = 0
        /// The number of frames the buffer is allowed to hold.
        public var bufferCapacity = 0
        /// The memory those frames occupy, in bytes.
        public var bufferedByteCount = 0
        /// The memory the window is allowed to use, in bytes: the share of
        /// ``AnimatedImageFramePool`` the player has been given.
        public var bufferByteLimit = 0

        /// The number of players drawing from the same decoded frames, this
        /// one included. More than one means the animation is on screen more
        /// than once and is being decoded and held once.
        public var sharingPlayerCount = 0

        /// The number of frames this player waited for a decode of since it
        /// was created.
        ///
        /// Larger than ``frameCount`` when the buffer can't hold the whole
        /// animation and frames are decoded again on every loop. Smaller when
        /// another player had already decoded them.
        public var decodedFrameCount = 0
        /// How long the most recent frame took to decode, in seconds.
        public var lastDecodeDuration: TimeInterval = 0
        /// The mean decode time across every frame decoded so far.
        public var averageDecodeDuration: TimeInterval = 0
        /// The slowest frame decode so far.
        public var maxDecodeDuration: TimeInterval = 0

        /// The number of frames actually shown.
        public var displayedFrameCount = 0
        /// The number of frames that were due before they finished decoding.
        ///
        /// No frame is skipped: each of these held the frame before it on
        /// screen past its delay. Steadily rising is the sign of a decoder
        /// that cannot keep up with the animation.
        public var bufferMissCount = 0
        /// The time the player has spent playing, in seconds.
        public var playbackTime: TimeInterval = 0

        /// The number of frames shown per second of playback.
        ///
        /// Compare it with ``AnimatedImageSource/nominalFrameRate``: a lower
        /// value means the animation is being stretched, by frames arriving
        /// late from the decoder or ticks arriving late from a busy main
        /// thread.
        public var effectiveFrameRate: Double {
            playbackTime > 0 ? Double(displayedFrameCount) / playbackTime : 0
        }

        /// `true` when every frame of the animation fits in the buffer, so
        /// each one is decoded exactly once.
        public var isFullyBuffered: Bool {
            bufferCapacity >= frameCount
        }
    }
}
