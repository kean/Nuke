// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO

/// Produces the frames of an animated image.
///
/// ``AnimatedImageFrameDecoder`` is the one implementation that ships; the
/// tests substitute one that releases a frame at a time.
protocol AnimatedImageFrameDecoding: Sendable {
    func decode(at index: Int) async -> AnimatedImageFrameDecoder.Frame?
}

/// Decodes the frames of an animated image, one at a time, off the main thread.
///
/// An actor because `CGImageSource` is not safe to use concurrently, and
/// because decoding in playback order is what the buffer wants anyway.
actor AnimatedImageFrameDecoder: AnimatedImageFrameDecoding {
    private let animation: AnimatedImageSource
    private let maxPixelSize: CGFloat?

    /// Created on the first decode: a view that is given an animation before
    /// it is laid out replaces its first player at the first layout, and that
    /// player should not parse the container for nothing.
    private lazy var source: CGImageSource? = animation.makeImageSource()

    /// A decoded frame and what it cost to produce.
    struct Frame: @unchecked Sendable {
        /// `CGImage` is immutable but predates `Sendable`, hence the unchecked
        /// conformance.
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
        // Image I/O composes the frame onto the canvas, applying the disposal
        // and blend modes of GIF and APNG.
        guard let image = CGImageSourceCreateImageAtIndex(source, index, AnimatedImageSource.imageSourceOptions) else {
            return nil
        }
        // The image is lazy: it decompresses the first time something draws
        // it, which would otherwise be the main thread. Drawing it here also
        // produces a bitmap in the format the compositor wants.
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
        // BGRA, the layout Core Animation uploads without converting.
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
        // Keep a wide-gamut image wide when the context accepts its color
        // space; fall back to sRGB rather than failing to draw.
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
/// Decoding every frame up front is the fastest way to run out of memory (a
/// 1000×1000 animation with 60 frames is 240 MB of bitmaps), so a buffer covers
/// a window of frames starting at the one on screen, and the frames outside it
/// are decoded as the window reaches them.
///
/// The frames belong to an ``AnimatedImageFrameStore`` shared by every player
/// of the same animation at the same size: the buffer is a playhead and a claim
/// on a range around it. The window size isn't the buffer's to decide either:
/// it says how many frames it could use (``wantedFrameCount``), and
/// ``AnimatedImageFramePool`` answers with a share of the memory every
/// animation on screen is sharing. When the whole animation fits, nothing is
/// ever evicted and each frame is decoded exactly once.
@MainActor
final class AnimatedImageFrameBuffer {
    /// Held strongly: it keeps the store's frames from being swept and is what
    /// the store builds its decoder from.
    let source: AnimatedImageSource

    /// The frames of this animation at this size, shared with every other
    /// player showing it.
    let store: AnimatedImageFrameStore

    /// The number of frames the buffer is allowed to hold.
    ///
    /// Two is the floor: with one, the next frame could only start decoding
    /// after the current one was dropped.
    var capacity: Int {
        max(Self.idleCapacity, min(store.windowLength, wantedFrameCount))
    }

    /// The number of frames the buffer would hold if the pool had the memory
    /// to spare: every frame up to the player's budget, and only
    /// ``idleCapacity`` while nobody is watching.
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
    /// A player that isn't playing sets it to `false`, which holds the buffer
    /// at ``idleCapacity``: a list of animations showing their first frame
    /// shouldn't each pin a full window of bitmaps.
    var fillsWindow = true {
        didSet {
            guard fillsWindow != oldValue else { return }
            // The new allotment is what drops the frames that no longer fit
            // and starts decoding into the room that opened up.
            pool.rebalance()
        }
    }

    /// Whether the buffer decodes at all. `true` by default.
    ///
    /// A view handed an animation before it knows what size to decode it at
    /// turns this off until it does, rather than decoding a full-size frame it
    /// is about to throw away.
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
    /// pressure, until ``restoreCapacity()`` takes it off.
    private var reducedCapacity: Int?

    private let pool: AnimatedImageFramePool
    private let frameCount: Int
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
    /// A frame shared with another player is counted in full by both: this is
    /// what the player draws from, not what it costs.
    /// ``AnimatedImageFramePool/totalCost`` counts a shared frame once.
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
        // A `deinit` isn't on the main actor, so the pool is asked to divide
        // the budget on the next turn, which also sweeps this member out of
        // the store.
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
    /// flight so that the frame is never offered. The decode itself is only
    /// cancelled if no other player was waiting for it.
    func setCurrentIndex(_ index: Int, isSeeking: Bool = false) {
        currentIndex = index
        store.didUpdateWindow(of: self, isSeeking: isSeeking)
    }

    /// Shrinks the window, dropping the frames that no longer fit.
    ///
    /// Used to respond to memory pressure. The buffer refills to the new
    /// capacity as playback continues.
    func reduceCapacity(to newCapacity: Int) {
        // Never below the two frames playback needs.
        reducedCapacity = max(Self.idleCapacity, min(newCapacity, reducedCapacity ?? newCapacity))
        // What it stops asking for goes back to the pool, which is the point.
        pool.rebalance()
        store.didUpdateWindow(of: self, isSeeking: false)
    }

    /// Takes the ceiling a memory warning put on the window back off, leaving
    /// the pool to size it again.
    ///
    /// Without it a buffer shrunk once would re-decode every frame of every
    /// loop for the life of the player.
    func restoreCapacity() {
        guard reducedCapacity != nil else { return }
        reducedCapacity = nil
        pool.rebalance()
        store.scheduleDecodeIfNeeded()
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
        // Offered even if the window has moved past the frame: the player is
        // the one that knows whether it has anything better to show.
        onFrame?(index)
    }

    /// The decode in flight, if there is one.
    ///
    /// For the tests, which hold a decode open and wait for the frame it
    /// produces rather than for the whole window.
    var currentDecode: Task<Void, Never>? { store.currentDecode }

    /// Waits until the window is full or until there is nothing left to decode.
    ///
    /// For the tests, which need a point where the buffer is settled rather
    /// than a sleep long enough to probably work.
    func waitUntilFull() async {
        while let task = store.currentDecode {
            await task.value
        }
    }
}
