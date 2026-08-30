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
/// A player is a model object with no opinion about how the frames are shown.
/// ``AnimatedImageView`` and ``AnimatedImage`` create one for you; you create
/// one yourself when you want to drive playback – or read
/// ``AnimatedImagePlayer/diagnostics`` – from your own view.
///
/// ## Observation
///
/// The player is an `ObservableObject`, so a SwiftUI view can read
/// ``isPlaying`` and ``isFinished`` and be redrawn when they change:
///
/// ```swift
/// @ObservedObject var player: AnimatedImagePlayer
///
/// Button(player.isPlaying ? "Pause" : "Play") {
///     player.isPlaying ? player.pause() : player.play()
/// }
/// ```
///
/// What is published is the playback state changing – it starts, stops,
/// finishes its loops, or something moves the playhead – and deliberately not
/// the animation running. The frames go to the view directly, and a SwiftUI
/// graph invalidated 20 times a second to redraw a picture the view has already
/// drawn is the cost this whole design exists to avoid. So
/// ``currentFrameIndex`` and ``completedLoopCount`` advance without a signal
/// while the animation plays: watch them through ``onLoop`` and ``onFinish``,
/// or sample ``diagnostics`` on a timer, which is what the demo app does.
///
/// ## Timing
///
/// Playback follows the wall clock rather than the decoder. Every tick of the
/// clock adds the elapsed time to a budget and the player advances through as
/// many frames as that budget covers, so an animation that takes three seconds
/// on paper takes three seconds on screen even when the main thread stalls or
/// the decoder falls behind. What suffers when the decoder can't keep up is the
/// number of frames actually shown (``Diagnostics/skippedFrameCount``), not the
/// duration – the same trade-off a video player makes.
///
/// The one animation that can't hold to the wall clock is one whose frames take
/// longer to decode than they are shown for. Skipping there would mean skipping
/// every frame, so the playhead waits for the decoder instead and the animation
/// plays slow rather than stopping.
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
    /// It stays yours. ``AnimatedImageView`` and ``AnimatedImage`` take the
    /// frames of a player they are given through a channel of their own, so
    /// handing one of them a player you drive a scrubber with doesn't quietly
    /// replace the handler that drives it.
    public var onFrame: ((PlatformImage) -> Void)?

    /// Called with the number of completed loops every time the animation
    /// wraps around.
    public var onLoop: ((Int) -> Void)?

    /// Called when the animation stops because it has played all of its loops.
    public var onFinish: (() -> Void)?

    /// The handler the views display the frames through.
    ///
    /// Separate from ``onFrame`` because there is only one of that and it
    /// belongs to whoever made the player. A view that installed itself there
    /// would replace whatever was already in it – with no diagnostic, and
    /// nothing to put back.
    var onFrameForDisplay: ((PlatformImage) -> Void)?

    let buffer: AnimatedImageFrameBuffer
    private let clock: any AnimatedImageClock
    private let memoryPressureGracePeriod: TimeInterval
    private var elapsed: TimeInterval = 0
    private var displayedFrameIndex: Int?
    private var counters = Counters()
    private var notificationObservers: [NotificationObserver] = []
    private var bufferRestore: Task<Void, Never>?

    /// How long a buffer stays shrunk after a memory warning: 60 seconds.
    ///
    /// The system decides what to kill in far less than that, so a minute is
    /// long enough for the pressure to be over, and short enough that an
    /// animation that is on screen all session doesn't spend the rest of it
    /// re-decoding every frame of every loop.
    static let defaultMemoryPressureGracePeriod: TimeInterval = 60

    /// Creates a player for the given image.
    public convenience init(source: AnimatedImageSource, options: Options = Options()) {
        self.init(source: source, options: options, clock: makeAnimatedImageClock())
    }

    init(
        source: AnimatedImageSource,
        options: Options,
        clock: any AnimatedImageClock,
        decoder: (any AnimatedImageFrameDecoding)? = nil,
        memoryPressureGracePeriod: TimeInterval = AnimatedImagePlayer.defaultMemoryPressureGracePeriod
    ) {
        self.source = source
        self.options = options
        self.clock = clock
        self.memoryPressureGracePeriod = memoryPressureGracePeriod
        self.buffer = AnimatedImageFrameBuffer(source: source, options: options, decoder: decoder)

        clock.preferredFrameRate = AnimatedImagePlayer.preferredFrameRate(for: source, options: options)
        clock.onTick = { [weak self] in self?.tick($0) }
        buffer.onFrame = { [weak self] in self?.frameDidDecode(at: $0) }
        // Start decoding right away: the first frame should be on screen
        // whether or not anything ever calls `play()`. Only the first frames
        // though – a player that never plays should not hold a full buffer.
        buffer.fillsWindow = false
        buffer.setCurrentIndex(0)
        registerForApplicationNotifications()
    }

    // The clock and the notification observer both stop themselves when the
    // player releases them: a `deinit` on a main-actor class can't reach back
    // into the actor to do it here.

    // MARK: Playback

    /// Starts or resumes playback.
    ///
    /// Does nothing if the animation has already finished; call ``restart()``
    /// to play it from the beginning, or ``seek(toFrame:)`` to pick up
    /// somewhere else.
    public func play() {
        guard !isPlaying, !isFinished else { return }
        isPlaying = true
        // Now the rest of the window is worth decoding.
        buffer.fillsWindow = true
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
    /// The index is clamped to the number of frames in the animation. Seeking
    /// moves the buffer window, so the frames around the destination start
    /// decoding immediately, and the frame itself appears as soon as it is
    /// ready – which is on the next run loop pass at the earliest.
    ///
    /// A player that has played all of its loops can be seeked and played
    /// again: it was finished with the loops it was asked for, not with the
    /// animation.
    public func seek(toFrame index: Int) {
        let index = min(max(0, index), source.frameCount - 1)
        // Assigned on every seek, whether or not it was set, because this is
        // also what publishes the move to anything observing the player: a
        // `@Published` property publishes on assignment, not on change.
        // `currentFrameIndex` – the thing that actually moved – can't do it
        // itself, because it moves on every frame of every loop, and
        // publishing there would put the SwiftUI graph on the frame clock.
        isFinished = false
        currentFrameIndex = index
        elapsed = 0
        // The frame being decoded is for somewhere the playhead has just left.
        // Left to finish, it would arrive as a frame the animation ran past,
        // which is the one case where the player moves the playhead back to
        // meet the decoder – and the seek would be undone by it.
        buffer.setCurrentIndex(index, isSeeking: true)
        display(frameAt: index)
    }

    // MARK: Memory

    /// Shrinks the frame buffer to its minimum size, dropping the decoded
    /// frames that don't fit.
    ///
    /// Called automatically when the system issues a memory warning. Playback
    /// continues: the frames are decoded again as they are needed, which costs
    /// CPU and is the trade the system is asking for. The buffer returns to its
    /// full size once the pressure has had time to pass, so a player that lives
    /// for a session doesn't pay for one warning forever.
    public func reduceMemoryUsage() {
        buffer.reduceCapacity(to: 2)
        // Waiting for the app to be backgrounded and come back is waiting for
        // something that mostly doesn't happen: a memory warning arrives while
        // the app is active, and usually on the screen the animation is on. A
        // sticker or a spinner would re-decode every frame of every loop from
        // the first warning of the session to the end of it.
        bufferRestore?.cancel()
        bufferRestore = Task { [weak self, memoryPressureGracePeriod] in
            try? await Task.sleep(for: .seconds(memoryPressureGracePeriod))
            guard !Task.isCancelled else { return }
            self?.buffer.restoreCapacity()
        }
    }

    /// Whether the player keeps a full window of decoded frames. `true` by
    /// default.
    ///
    /// Set it to `false` for a player nobody is watching – a view that has
    /// scrolled off screen. It keeps the frame on display and the one after it
    /// and gives the rest of the window back, so a list of animations that have
    /// been scrolled past doesn't hold a memory budget each for frames nobody
    /// is going to see. ``play()`` sets it back to `true`.
    ///
    /// ``AnimatedImageView`` does this for you when it pauses because it left
    /// its window – but not when playback is paused in place, where the frames
    /// are worth keeping so that resuming doesn't stall.
    public var keepsFullBuffer: Bool {
        get { buffer.fillsWindow }
        set { buffer.fillsWindow = newValue }
    }

    // MARK: Diagnostics

    /// A snapshot of what the player and its buffer are doing.
    public var diagnostics: Diagnostics {
        var diagnostics = Diagnostics()
        diagnostics.frameCount = source.frameCount
        diagnostics.currentFrameIndex = currentFrameIndex
        diagnostics.completedLoopCount = completedLoopCount
        diagnostics.bufferedFrameCount = buffer.count
        diagnostics.bufferCapacity = buffer.capacity
        diagnostics.bufferedByteCount = buffer.byteCount
        diagnostics.decodedFrameCount = buffer.decodedFrameCount
        diagnostics.lastDecodeDuration = buffer.lastDecodeDuration
        diagnostics.averageDecodeDuration = buffer.decodedFrameCount > 0
            ? buffer.totalDecodeDuration / Double(buffer.decodedFrameCount) : 0
        diagnostics.maxDecodeDuration = buffer.maxDecodeDuration
        diagnostics.displayedFrameCount = counters.displayedFrameCount
        diagnostics.skippedFrameCount = counters.skippedFrameCount
        diagnostics.bufferMissCount = counters.bufferMissCount
        diagnostics.playbackTime = counters.playbackTime
        return diagnostics
    }

    /// Whether the player decodes frames at all.
    ///
    /// ``AnimatedImageView`` turns it off for the moment between being given an
    /// animation and knowing what size to decode it at, so that the frames it
    /// is going to throw away are never decoded in the first place. Not public:
    /// a player nobody has suspended always decodes.
    var isDecodingEnabled: Bool {
        get { buffer.isDecodingEnabled }
        set { buffer.isDecodingEnabled = newValue }
    }

    /// Returns `true` if the frame at the given index is decoded and in memory.
    ///
    /// Together with ``Diagnostics/bufferCapacity`` it is enough to draw what
    /// the buffer is holding, which is what the diagnostics overlay in the demo
    /// app does.
    public func isFrameBuffered(_ index: Int) -> Bool {
        buffer.frame(at: index) != nil
    }

    // MARK: Private

    private func tick(_ delta: TimeInterval) {
        guard isPlaying, !isFinished else { return }

        // Playback usually starts before the first frame has been decoded.
        // Counting that time would spend it on frames nobody sees: frame 0
        // arrives when the playhead is already past it and is thrown away. The
        // poster frame is on screen in the meantime, so the wait is free – and
        // it ends either way, because a frame the decoder refuses stops being
        // pending.
        guard displayedFrameIndex != nil || !buffer.isPending(currentFrameIndex) else {
            return
        }

        // A clock that was starved – the app was in the background, the main
        // thread was blocked – reports the whole gap. Replaying it would make
        // the animation lurch, so the step is capped and the animation simply
        // misses that time.
        let step = min(delta, options.maxTimeStep) * options.playbackRate
        guard step > 0 else { return }
        counters.playbackTime += step
        elapsed += step

        var advanced = 0
        while elapsed >= source.delays[currentFrameIndex] {
            elapsed -= source.delays[currentFrameIndex]
            guard advanceFrame() else { break }
            advanced += 1
            if advanced >= source.frameCount {
                // More than a full loop behind. Catching up frame by frame from
                // here is pointless: drop the debt and carry on.
                elapsed = 0
                break
            }
        }
        guard advanced > 0 else { return }

        counters.skippedFrameCount += advanced - 1
        buffer.setCurrentIndex(currentFrameIndex)
        display(frameAt: currentFrameIndex)
    }

    /// Moves to the next frame. Returns `false` if the animation has finished.
    private func advanceFrame() -> Bool {
        let next = currentFrameIndex + 1
        guard next >= source.frameCount else {
            currentFrameIndex = next
            return true
        }
        completedLoopCount += 1
        onLoop?(completedLoopCount)
        if let limit = repeatLimit, completedLoopCount >= limit {
            isFinished = true
            isPlaying = false
            clock.isPaused = true
            onFinish?()
            return false
        }
        currentFrameIndex = 0
        return true
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
        guard let cgImage = buffer.frame(at: index) else {
            // The decoder is behind. The previous frame stays on screen and
            // this one is displayed by `frameDidDecode(at:)` if it arrives
            // while it is still the current one.
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
        guard index != currentFrameIndex else {
            return display(frameAt: index)
        }
        // The frame decoded after the playhead had already gone past it. If the
        // frame the playhead is on isn't decoded either, dropping this one
        // would leave nothing to show: the next decode starts at the playhead,
        // takes just as long, and is just as late, and the animation stops on
        // whatever is on screen while the decoder keeps burning a core. Showing
        // the late frame and moving the playhead back to it degrades playback
        // to the speed of the decoder, which is the trade a video player makes.
        //
        // Only while the animation is running, though. A player that is paused,
        // or that has stopped on the last frame it was asked to play, is on the
        // frame it is on deliberately, and a decode that lands afterwards is
        // not a reason to move it.
        guard isPlaying, buffer.frame(at: currentFrameIndex) == nil else { return }
        currentFrameIndex = index
        elapsed = 0
        display(frameAt: index)
        buffer.setCurrentIndex(index)
    }

    private func makeImage(_ cgImage: CGImage) -> PlatformImage {
#if canImport(UIKit)
        UIImage(cgImage: cgImage, scale: options.scale, orientation: .up)
#else
        // `NSImage` has no scale of its own – what it has is a size in points
        // and a bitmap in pixels, and the scale is the ratio between them. Built
        // at the pixel size it draws twice as large as it should wherever
        // nothing rescales it, `imageScaling` of `.scaleNone` being the case.
        let scale = options.scale > 0 ? options.scale : 1
        return NSImage(cgImage: cgImage, size: NSSize(
            width: CGFloat(cgImage.width) / scale,
            height: CGFloat(cgImage.height) / scale
        ))
#endif
    }

    /// The rate to run the clock at, or `0` to let it use its own.
    ///
    /// Most animations are far slower than the display, and waking up 60 or 120
    /// times a second to show 10 frames is wasted power. The rate asked for is
    /// twice the fastest frame in the animation, which guarantees a tick to
    /// show every frame on: at exactly one tick per frame, the two rates beat
    /// against each other and frames are passed over.
    ///
    /// Above 15 frames per second there is nothing to win – the clock would be
    /// asking for the rate it already runs at – so the hint is dropped.
    private static func preferredFrameRate(for source: AnimatedImageSource, options: Options) -> Double {
        guard let shortest = source.delays.min(), shortest > 0 else {
            return 0
        }
        let ticksPerSecond = (1 / shortest) * max(options.playbackRate, 1) * 2
        return ticksPerSecond <= 30 ? ticksPerSecond : 0
    }

    private func registerForApplicationNotifications() {
#if os(iOS) || os(tvOS) || os(visionOS)
        notificationObservers = [
            NotificationObserver(name: UIApplication.didReceiveMemoryWarningNotification) { [weak self] in
                self?.reduceMemoryUsage()
            },
            // Coming back to the foreground is the clearest signal there is
            // that whatever the memory warning was about is over.
            NotificationObserver(name: UIApplication.didBecomeActiveNotification) { [weak self] in
                self?.bufferRestore?.cancel()
                self?.buffer.restoreCapacity()
            }
        ]
#endif
    }

    /// The counters the player itself keeps; the rest come from the buffer.
    private struct Counters {
        var displayedFrameCount = 0
        var skippedFrameCount = 0
        var bufferMissCount = 0
        var playbackTime: TimeInterval = 0
    }
}

/// A notification subscription that unsubscribes when it is released.
///
/// The player can't do it from its own `deinit`: it is isolated to the main
/// actor, and a `deinit` isn't, so it can't so much as read the token. An
/// unisolated object that owns the token can.
private final class NotificationObserver {
    private let token: any NSObjectProtocol

    init(name: Notification.Name, handler: @escaping @MainActor () -> Void) {
        token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated(handler)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}

extension AnimatedImagePlayer {
    /// The knobs that change how an animation is played and how much memory it
    /// is allowed to use.
    public struct Options: Sendable {
        /// How many times to play the animation. ``RepeatCount/image`` by
        /// default, which honors what the file asks for.
        public var repeatCount: RepeatCount = .image

        /// The speed multiplier. `1` by default.
        public var playbackRate: Double = 1

        /// The memory the decoded frames may occupy, in bytes. 10 MB by default.
        ///
        /// An animation whose frames all fit is decoded once and then replayed
        /// from memory; a larger one is decoded continuously into a sliding
        /// window of `maxBufferSize / bytesPerFrame` frames. The buffer never
        /// holds fewer than two frames, so an animation with very large frames
        /// can exceed this figure – there is no way to play one without keeping
        /// two frames around.
        public var maxBufferSize = 10 * 1_048_576

        /// The longest side, in pixels, the decoded frames may have. `nil` –
        /// no downsampling – by default.
        ///
        /// Set it to the size of the view in pixels to play an animation that
        /// is much larger than the space it is displayed in: the frames are
        /// scaled as they are decoded, which cuts the memory each one costs by
        /// the square of the scale, at the price of a resample per frame.
        public var maxPixelSize: CGFloat?

        /// The scale of the images the player produces. `1` by default.
        public var scale: CGFloat = 1

        /// The largest gap between two clock ticks the player will act on,
        /// in seconds. `1` by default.
        ///
        /// Time beyond this is dropped rather than replayed, which is what
        /// keeps an animation from spinning through hundreds of frames when the
        /// app comes back from the background.
        public var maxTimeStep: TimeInterval = 1

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

    /// What the player and its buffer are doing, for logging, tests, and the
    /// diagnostics overlay in the demo app.
    public struct Diagnostics: Sendable {
        /// Creates an empty snapshot, which is what a player that hasn't run
        /// yet would report.
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

        /// The number of frames decoded since the player was created. Larger
        /// than ``frameCount`` when the buffer can't hold the whole animation
        /// and frames are decoded again on every loop.
        public var decodedFrameCount = 0
        /// How long the most recent frame took to decode, in seconds.
        public var lastDecodeDuration: TimeInterval = 0
        /// The mean decode time across every frame decoded so far.
        public var averageDecodeDuration: TimeInterval = 0
        /// The slowest frame decode so far.
        public var maxDecodeDuration: TimeInterval = 0

        /// The number of frames actually shown.
        public var displayedFrameCount = 0
        /// The number of frames passed over because the player was behind the
        /// wall clock. Steadily rising is the sign of a decoder that cannot
        /// keep up with the animation.
        public var skippedFrameCount = 0
        /// The number of times a frame was due and had not been decoded yet.
        public var bufferMissCount = 0
        /// The time the player has spent playing, in seconds.
        public var playbackTime: TimeInterval = 0

        /// The number of frames shown per second of playback.
        ///
        /// Compare it with ``AnimatedImageSource/nominalFrameRate``: a lower
        /// value means frames are being skipped.
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
