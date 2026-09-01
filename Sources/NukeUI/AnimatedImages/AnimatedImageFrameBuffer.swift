// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO

/// Produces the frames of an animated image.
///
/// The one implementation that ships is ``AnimatedImageFrameDecoder``. The
/// tests substitute one they release a frame at a time: a player that outruns
/// its decoder is otherwise a race, and the test would have to make the frames
/// slow enough to decode and hope.
protocol AnimatedImageFrameDecoding: Sendable {
    func decode(at index: Int) async -> AnimatedImageFrameDecoder.Frame?
}

/// Decodes the frames of an animated image, one at a time, off the main thread.
///
/// It is an actor because `CGImageSource` is not safe to use concurrently and
/// because decoding one frame at a time in playback order is what the buffer
/// wants anyway: decoding several frames in parallel would finish the ones that
/// are needed last just as soon as the one that is needed next.
actor AnimatedImageFrameDecoder: AnimatedImageFrameDecoding {
    private let animation: AnimatedImageSource
    private let maxPixelSize: CGFloat?

    /// Created on the first decode rather than up front.
    ///
    /// A view that is given an animation before it is laid out builds a player
    /// with decoding disabled and replaces it at the first layout with one that
    /// decodes for the size it settled. Building the image source in the
    /// initializer meant the discarded player parsed the container for nothing,
    /// on the main thread, once per animation displayed.
    private lazy var source: CGImageSource? = animation.makeImageSource()

    /// A decoded frame and what it cost to produce.
    struct Frame: @unchecked Sendable {
        /// A `CGImage` backed by a bitmap this decoder owns. `CGImage` is
        /// immutable, but it predates `Sendable` and isn't annotated, hence
        /// the unchecked conformance.
        let image: CGImage
        /// How long the decode took, in seconds.
        let duration: TimeInterval
        /// The size of the bitmap in bytes.
        let byteCount: Int
    }

    /// - parameter maxPixelSize: The longest side, in pixels, the decoded
    /// frames may have. Larger frames are scaled down.
    init(source: AnimatedImageSource, maxPixelSize: CGFloat?) {
        self.animation = source
        self.maxPixelSize = maxPixelSize
    }

    /// Decodes and draws the frame at the given index.
    func decode(at index: Int) -> Frame? {
        guard let source, !Task.isCancelled else {
            return nil
        }
        let start = monotonicTime()
        // Image I/O composes the frame onto the animation canvas – it applies
        // the disposal and blend modes of GIF and APNG – so what comes back is
        // a complete picture, not the delta the container stores.
        guard let image = CGImageSourceCreateImageAtIndex(source, index, AnimatedImageSource.imageSourceOptions) else {
            return nil
        }
        // The image Image I/O hands back is lazy: it decompresses the first
        // time something draws it, which without this step is the main thread,
        // in the middle of a frame. Drawing it here moves that cost to this
        // actor and produces a bitmap in the format the compositor wants.
        let prepared = draw(image) ?? image
        return Frame(
            image: prepared,
            duration: monotonicTime() - start,
            byteCount: prepared.bytesPerRow * prepared.height
        )
    }

    private func draw(_ image: CGImage) -> CGImage? {
        let size = targetSize(for: image)
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        guard let context = makeContext(size: size, isOpaque: image.isOpaque, colorSpace: image.colorSpace) else {
            return nil
        }
        context.draw(image, in: CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height)))
        return context.makeImage()
    }

    private func targetSize(for image: CGImage) -> (width: Int, height: Int) {
        guard let maxPixelSize, maxPixelSize > 0 else {
            return (image.width, image.height)
        }
        let longestSide = CGFloat(max(image.width, image.height))
        guard longestSide > maxPixelSize else {
            return (image.width, image.height)
        }
        let scale = maxPixelSize / longestSide
        return (max(1, Int((CGFloat(image.width) * scale).rounded())),
                max(1, Int((CGFloat(image.height) * scale).rounded())))
    }

    private func makeContext(size: (width: Int, height: Int), isOpaque: Bool, colorSpace: CGColorSpace?) -> CGContext? {
        // 32-bit little-endian with alpha first is BGRA in memory, the layout
        // Core Animation uploads without converting.
        let alphaInfo: CGImageAlphaInfo = isOpaque ? .noneSkipFirst : .premultipliedFirst
        let bitmapInfo = alphaInfo.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        func makeContext(_ colorSpace: CGColorSpace) -> CGContext? {
            CGContext(
                data: nil,
                width: size.width,
                height: size.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        }
        // Keep a wide-gamut image wide, but only for the color spaces a bitmap
        // context of this layout accepts; anything else falls back to sRGB
        // rather than failing to draw.
        if let colorSpace, colorSpace.model == .rgb, let context = makeContext(colorSpace) {
            return context
        }
        return makeContext(CGColorSpaceCreateDeviceRGB())
    }
}

extension CGImage {
    var isOpaque: Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: true
        default: false
        }
    }
}

/// One player's sliding window over the frames of an animation.
///
/// Decoding every frame up front is the fastest way to play an animation and
/// the fastest way to run out of memory: a 1000×1000 animation with 60 frames
/// is 240 MB of bitmaps. So a buffer covers a window of frames starting at the
/// one being displayed, and the frames outside it are decoded as the window
/// reaches them.
///
/// The frames themselves belong to an ``AnimatedImageFrameStore``, which every
/// player of the same animation at the same size shares: the buffer is a
/// playhead and a claim on a range around it, not a private pile of bitmaps.
/// Twenty views of one sticker are twenty buffers, one store, one decoder, and
/// one animation's worth of memory.
///
/// How large the window is isn't the buffer's to decide either. It says how
/// many frames it could use – ``wantedFrameCount`` – its store adds that up
/// with what every other player of the same animation is asking for, and the
/// ``AnimatedImageFramePool`` answers with a share of the memory every
/// animation on screen is sharing.
///
/// When the whole animation fits in that share the window covers every frame,
/// nothing is ever evicted, and each frame is decoded exactly once no matter
/// how long the animation plays or how many views are playing it.
@MainActor
final class AnimatedImageFrameBuffer {
    /// The animation being played.
    ///
    /// Held strongly: it is what keeps the store's frames from being swept, and
    /// what the store builds its decoder out of.
    let source: AnimatedImageSource

    /// The frames of this animation at this size, shared with every other
    /// player showing it.
    let store: AnimatedImageFrameStore

    /// The number of frames the buffer is allowed to hold.
    ///
    /// Two is the floor: with one, the next frame can only start decoding after
    /// the current one is dropped, and playback stalls on every single frame.
    /// An animation whose frames are so large that two of them exceed the share
    /// is over it either way.
    var capacity: Int {
        max(Self.idleCapacity, min(store.windowLength, wantedFrameCount))
    }

    /// The number of frames the buffer would hold if the pool had the memory to
    /// spare: every frame of the animation, up to the budget the player was
    /// created with, and only ``idleCapacity`` while nobody is watching.
    var wantedFrameCount: Int {
        var frames = fillsWindow ? frameCount : Self.idleCapacity
        frames = min(frames, affordableFrameCount)
        frames = min(frames, reducedCapacity ?? frames)
        return max(Self.idleCapacity, min(frameCount, frames))
    }

    /// The range of frame indexes the buffer is claiming, which may run past
    /// ``frameCount`` and wrap around.
    var window: Range<Int> {
        currentIndex..<(currentIndex + capacity)
    }

    /// The memory the buffer's window is allowed to occupy, in bytes.
    var allotment: Int { capacity * bytesPerFrame }

    /// The frame the player is on.
    private(set) var currentIndex = 0

    /// Whether the buffer fills its whole window. `true` by default.
    ///
    /// A player that has not started playing sets it to `false`, which holds
    /// the buffer at ``idleCapacity``. A list of animations that are all
    /// showing their first frame should not each pin a full buffer's worth of
    /// bitmaps, and the frames would be decoded for nobody – and what they give
    /// back goes to the animations that are actually playing.
    var fillsWindow = true {
        didSet {
            guard fillsWindow != oldValue else { return }
            // The pool answers with a new allotment, and it is that which
            // drops the frames that no longer fit and starts decoding into the
            // room that just opened up.
            pool.rebalance()
        }
    }

    /// Whether the buffer decodes at all. `true` by default.
    ///
    /// A view that is handed an animation before it knows what size to decode
    /// it at turns this off until it does. The alternative is to decode a frame
    /// at the full size of the animation and throw it away, along with the
    /// player built to produce it, a moment later.
    var isDecodingEnabled = true {
        didSet {
            guard isDecodingEnabled != oldValue else { return }
            if isDecodingEnabled {
                store.scheduleDecodeIfNeeded()
            } else {
                store.memberDidStopDecoding(self)
            }
        }
    }

    /// What the buffer holds while ``fillsWindow`` is off: the frame on screen
    /// and the one after it, so that playback starts without a stall.
    static let idleCapacity = 2

    /// Called with the index of a frame as soon as it is decoded.
    var onFrame: ((Int) -> Void)?

    /// The ceiling ``reduceCapacity(to:)`` puts on the window under memory
    /// pressure, until ``restoreCapacity()`` takes it off again.
    private var reducedCapacity: Int?

    private let pool: AnimatedImageFramePool
    private let frameCount: Int
    /// The memory one decoded frame occupies, at the size it is decoded at.
    private let bytesPerFrame: Int
    /// The number of frames the player is willing to hold, whatever the pool
    /// has to spare.
    private let affordableFrameCount: Int

    // Diagnostics
    private(set) var decodedFrameCount = 0
    private(set) var lastDecodeDuration: TimeInterval = 0
    private(set) var totalDecodeDuration: TimeInterval = 0
    private(set) var maxDecodeDuration: TimeInterval = 0

    /// The number of frames in the window that are decoded.
    var count: Int { store.decodedFrameCount(in: window) }

    /// The memory those frames occupy, in bytes.
    ///
    /// Frames shared with another player are counted here in full and once
    /// again there: what each player is drawing from, not what it is costing.
    /// ``AnimatedImageFramePool/totalCost`` is the figure that counts a shared
    /// frame once.
    var byteCount: Int { store.byteCount(in: window) }

    /// `true` when there is nothing left to decode in the current window.
    var isFull: Bool { nextMissingIndex() == nil }

    /// - parameter decoder: The decoder to pull the frames from. The tests pass
    /// one of their own; everything else takes the default.
    init(
        source: AnimatedImageSource,
        options: AnimatedImagePlayer.Options,
        pool: AnimatedImageFramePool = .shared,
        decoder: (any AnimatedImageFrameDecoding)? = nil
    ) {
        self.source = source
        self.frameCount = source.frameCount
        self.pool = pool
        self.store = pool.store(for: source, maxPixelSize: options.maxPixelSize, decoder: decoder)
        self.bytesPerFrame = store.bytesPerFrame
        self.affordableFrameCount = bytesPerFrame > 0 ? options.maxBufferSize / bytesPerFrame : source.frameCount
        // Last, because it is what hands the store its first allotment.
        store.add(self)
        pool.rebalance()
    }

    deinit {
        // The window goes with the buffer, so the frames only it was claiming
        // are the pool's to hand out again. It can't be told from here – a
        // `deinit` isn't on the main actor – so it is asked to divide the
        // budget on the next turn, which is also what sweeps this member out
        // of the store.
        pool.setNeedsRebalance()
    }

    /// `true` while the store still expects to produce the frame at the given
    /// index: it is neither decoded nor one the decoder has refused.
    func isPending(_ index: Int) -> Bool {
        store.isPending(index)
    }

    /// Returns the frame at the given index if it has been decoded.
    func frame(at index: Int) -> CGImage? {
        store.frame(at: index)
    }

    /// `true` when the buffer is claiming the frame at the given index and is
    /// in a position to use it.
    func wants(_ index: Int) -> Bool {
        isDecodingEnabled && isInWindow(index)
    }

    /// Moves the window to start at the given index and refills it.
    ///
    /// - parameter isSeeking: Whether the window is being moved somewhere the
    /// animation was not heading, which drops the buffer from the decode in
    /// flight. That frame is for a place the playhead has left, and offering it
    /// would tell the player about a frame nobody asked for. There is no
    /// stopping it mid-`CGImageSourceCreateImageAtIndex`, so what this buys is
    /// that the frame is never offered – and it is only cancelled outright if
    /// no other player was waiting for it.
    func setCurrentIndex(_ index: Int, isSeeking: Bool = false) {
        currentIndex = index
        store.didUpdateWindow(of: self, isSeeking: isSeeking)
    }

    /// Shrinks the window, dropping the frames that no longer fit.
    ///
    /// Used to respond to memory pressure. The buffer refills to the new
    /// capacity as playback continues.
    func reduceCapacity(to newCapacity: Int) {
        // Never below the two frames playback needs, whatever it is asked for.
        reducedCapacity = max(Self.idleCapacity, min(newCapacity, reducedCapacity ?? newCapacity))
        // What it stops asking for goes back to the pool, which is the point:
        // a memory warning reaches every player, and the frames they all give
        // back are what the system asked for.
        pool.rebalance()
        store.didUpdateWindow(of: self, isSeeking: false)
    }

    /// Takes the ceiling a memory warning put on the window back off, leaving
    /// the pool to say how large it is again.
    ///
    /// Without it a buffer shrunk once stays shrunk for the life of the player:
    /// an animation that is on screen all session – a sticker, a spinner –
    /// would re-decode every frame of every loop forever because of a single
    /// memory warning, long after the pressure that caused it was over.
    func restoreCapacity() {
        guard reducedCapacity != nil else { return }
        reducedCapacity = nil
        pool.rebalance()
        store.scheduleDecodeIfNeeded()
    }

    /// Drops every decoded frame of the animation and stops the decode in
    /// flight.
    ///
    /// The frames belong to the store, so this reaches every player of the same
    /// animation. Nothing in playback calls it: shrinking a window is
    /// ``reduceCapacity(to:)``, which leaves the other players alone.
    func removeAll() {
        store.removeAllFrames()
    }

    private func isInWindow(_ index: Int) -> Bool {
        let offset = (index - currentIndex + frameCount) % frameCount
        return offset < capacity
    }

    private func nextMissingIndex() -> Int? {
        for offset in 0..<min(capacity, frameCount) {
            let index = (currentIndex + offset) % frameCount
            if store.isPending(index) {
                return index
            }
        }
        return nil
    }

    /// Called by the store with every frame this buffer was waiting for.
    func storeDidDecodeFrame(at index: Int, duration: TimeInterval) {
        decodedFrameCount += 1
        lastDecodeDuration = duration
        totalDecodeDuration += duration
        maxDecodeDuration = max(maxDecodeDuration, duration)
        // The window may have moved past this frame while it was being decoded.
        // It is offered anyway: the player is the one that knows whether it has
        // anything better to show, and it moves the window back if it doesn't.
        onFrame?(index)
    }

    /// The decode in flight, if there is one.
    ///
    /// Exists for the tests, which hold a decode open and need to wait for the
    /// frame it produces to land – and so cannot use ``waitUntilFull()``,
    /// which waits for the whole window.
    var currentDecode: Task<Void, Never>? { store.currentDecode }

    /// Waits until the window is full or until there is nothing left to decode.
    ///
    /// Exists for the tests, which need a point where the state of the buffer
    /// is settled rather than a sleep long enough to probably work.
    func waitUntilFull() async {
        while let task = store.currentDecode {
            await task.value
        }
    }
}
