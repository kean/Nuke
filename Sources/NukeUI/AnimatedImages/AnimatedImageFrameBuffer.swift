// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO

/// Decodes the frames of an animated image, one at a time, off the main thread.
///
/// It is an actor because `CGImageSource` is not safe to use concurrently and
/// because decoding one frame at a time in playback order is what the buffer
/// wants anyway: decoding several frames in parallel would finish the ones that
/// are needed last just as soon as the one that is needed next.
actor AnimatedImageFrameDecoder {
    private let source: CGImageSource?
    private let maxPixelSize: CGFloat?

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
    init(data: Data, maxPixelSize: CGFloat?) {
        self.source = CGImageSourceCreateWithData(data as CFData, imageSourceOptions)
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
        guard let image = CGImageSourceCreateImageAtIndex(source, index, imageSourceOptions) else {
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

/// A bounded, sliding window of decoded frames.
///
/// Decoding every frame of an animation up front is the fastest way to play it
/// and the fastest way to run out of memory: a 1000×1000 animation with 60
/// frames is 240 MB of bitmaps. The buffer holds a window of frames starting at
/// the one being displayed, refills it in playback order as the window moves,
/// and drops what has fallen behind.
///
/// When the whole animation fits in the budget the window covers every frame,
/// nothing is ever evicted, and each frame is decoded exactly once no matter
/// how long the animation plays.
@MainActor
final class AnimatedImageFrameBuffer {
    /// The number of frames the buffer is allowed to hold.
    var capacity: Int { fillsWindow ? windowCapacity : min(windowCapacity, Self.idleCapacity) }

    /// Whether the buffer fills its whole window. `true` by default.
    ///
    /// A player that has not started playing sets it to `false`, which holds
    /// the buffer at ``idleCapacity``. A list of animations that are all
    /// showing their first frame should not each pin a full buffer's worth of
    /// bitmaps, and the frames would be decoded for nobody.
    var fillsWindow = true {
        didSet {
            guard fillsWindow != oldValue else { return }
            evict()
            decodeNextFrame()
        }
    }

    /// What the buffer holds while ``fillsWindow`` is off: the frame on screen
    /// and the one after it, so that playback starts without a stall.
    static let idleCapacity = 2

    /// Called with the index of a frame as soon as it is decoded.
    var onFrame: ((Int) -> Void)?

    private var windowCapacity: Int

    private let decoder: AnimatedImageFrameDecoder
    private let frameCount: Int
    private var frames: [Int: CGImage] = [:]
    /// The frames the decoder refused. Without this, a truncated animation
    /// would put the buffer in a loop, retrying the frame it can never produce.
    private var failedIndexes: Set<Int> = []
    private var currentIndex = 0
    private var task: Task<Void, Never>?

    // Diagnostics
    private(set) var byteCount = 0
    private(set) var decodedFrameCount = 0
    private(set) var lastDecodeDuration: TimeInterval = 0
    private(set) var totalDecodeDuration: TimeInterval = 0
    private(set) var maxDecodeDuration: TimeInterval = 0

    /// The number of frames currently decoded.
    var count: Int { frames.count }

    /// `true` when there is nothing left to decode in the current window.
    var isFull: Bool { nextMissingIndex() == nil }

    init(source: AnimatedImageSource, options: AnimatedImagePlayer.Options) {
        self.decoder = AnimatedImageFrameDecoder(data: source.data, maxPixelSize: options.maxPixelSize)
        self.frameCount = source.frameCount
        self.windowCapacity = AnimatedImageFrameBuffer.capacity(for: source, options: options)
    }

    deinit {
        task?.cancel()
    }

    /// Returns the number of frames to keep in memory at once.
    ///
    /// The budget is a byte count rather than a frame count because that is
    /// what actually matters: 60 thumbnails and 60 full-screen frames are the
    /// same number of frames and two orders of magnitude apart in memory.
    static func capacity(for source: AnimatedImageSource, options: AnimatedImagePlayer.Options) -> Int {
        var bytesPerFrame = source.bytesPerFrame
        if let maxPixelSize = options.maxPixelSize, maxPixelSize > 0 {
            let longestSide = max(source.size.width, source.size.height)
            if longestSide > maxPixelSize {
                let scale = maxPixelSize / longestSide
                bytesPerFrame = Int(Double(bytesPerFrame) * Double(scale * scale))
            }
        }
        guard bytesPerFrame > 0 else {
            return source.frameCount
        }
        let affordable = options.maxBufferSize / bytesPerFrame
        // Two frames is the floor: with one, the next frame can only start
        // decoding after the current one is dropped, and playback stalls on
        // every single frame. An animation whose frames are so large that two
        // of them exceed the budget is over the budget either way.
        return min(source.frameCount, max(idleCapacity, affordable))
    }

    /// Returns the frame at the given index if it has been decoded.
    func frame(at index: Int) -> CGImage? {
        frames[index]
    }

    /// Moves the window to start at the given index and refills it.
    func setCurrentIndex(_ index: Int) {
        currentIndex = index
        evict()
        decodeNextFrame()
    }

    /// Shrinks the window, dropping the frames that no longer fit.
    ///
    /// Used to respond to memory pressure. The buffer refills to the new
    /// capacity as playback continues.
    func reduceCapacity(to newCapacity: Int) {
        windowCapacity = max(Self.idleCapacity, min(windowCapacity, newCapacity))
        evict()
    }

    /// Drops every decoded frame and stops the decoding in flight.
    func removeAll() {
        task?.cancel()
        task = nil
        frames.removeAll()
        byteCount = 0
    }

    private func evict() {
        guard capacity < frameCount else {
            return // The whole animation fits: never evict, never re-decode
        }
        for (index, image) in frames where !isInWindow(index) {
            frames[index] = nil
            byteCount -= image.bytesPerRow * image.height
        }
    }

    private func isInWindow(_ index: Int) -> Bool {
        let offset = (index - currentIndex + frameCount) % frameCount
        return offset < capacity
    }

    /// Starts decoding the first frame of the window that is missing, if any.
    ///
    /// Only one decode is ever in flight. The next one is scheduled when it
    /// finishes, which keeps the work in playback order and keeps a slow
    /// decoder from filling the cooperative pool with frames nobody is waiting
    /// for yet.
    private func decodeNextFrame() {
        guard task == nil, let index = nextMissingIndex() else {
            return
        }
        let decoder = self.decoder
        task = Task { [weak self] in
            let frame = await decoder.decode(at: index)
            // The cancellation check comes first: `removeAll` clears the handle
            // itself, so a cancelled decode that cleared it again would drop
            // the handle of the decode that started in its place and let a
            // third one begin alongside it.
            guard let self, !Task.isCancelled else { return }
            self.task = nil
            if let frame {
                self.insert(frame, at: index)
            } else {
                self.failedIndexes.insert(index)
            }
            self.decodeNextFrame()
        }
    }

    private func nextMissingIndex() -> Int? {
        for offset in 0..<min(capacity, frameCount) {
            let index = (currentIndex + offset) % frameCount
            if frames[index] == nil && !failedIndexes.contains(index) {
                return index
            }
        }
        return nil
    }

    private func insert(_ frame: AnimatedImageFrameDecoder.Frame, at index: Int) {
        decodedFrameCount += 1
        lastDecodeDuration = frame.duration
        totalDecodeDuration += frame.duration
        maxDecodeDuration = max(maxDecodeDuration, frame.duration)

        // The window may have moved on while this frame was being decoded – a
        // late frame nobody will display is not worth the memory.
        guard isInWindow(index), frames[index] == nil else {
            return
        }
        frames[index] = frame.image
        byteCount += frame.byteCount
        onFrame?(index)
    }

    /// Waits until the window is full or until there is nothing left to decode.
    ///
    /// Exists for the tests, which need a point where the state of the buffer
    /// is settled rather than a sleep long enough to probably work.
    func waitUntilFull() async {
        while let task {
            await task.value
        }
    }
}
