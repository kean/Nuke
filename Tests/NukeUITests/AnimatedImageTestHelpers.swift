// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
@testable import Nuke
@testable import NukeUI

/// A clock that ticks when a test tells it to.
///
/// Playback is a pure function of the ticks it receives, so with this in place
/// the tests assert on exact frame indexes instead of sleeping and hoping.
@MainActor
final class ManualClock: AnimatedImageClock {
    var onTick: ((TimeInterval) -> Void)?
    var isPaused: Bool = true
    var preferredFrameRate: Double = 0

    /// Advances the clock. Like a real one, it delivers nothing while paused.
    func tick(_ delta: TimeInterval) {
        guard !isPaused else { return }
        onTick?(delta)
    }
}

extension AnimatedImagePlayer.Options {
    /// A budget no frame fits in, which puts the buffer at its two-frame floor
    /// and makes the window slide.
    static var twoFrameBuffer: AnimatedImagePlayer.Options {
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = 1
        return options
    }
}

/// The priority a decode runs at.
///
/// Spelled out because `Nuke` has a `TaskPriority` of its own and the test
/// target imports both.
typealias DecodePriority = _Concurrency.TaskPriority

/// A decoder that produces a frame only once the test releases it.
///
/// A player that outruns its decoder is otherwise a race: the test would have
/// to make the frames big enough to decode slowly and hope they stay slow.
actor GatedFrameDecoder: AnimatedImageFrameDecoding {
    private let decoder: AnimatedImageFrameDecoder
    private var gates: [Int: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<Int> = []
    private var startedPriorities: [Int: DecodePriority] = [:]
    private var priorityWaiters: [Int: CheckedContinuation<DecodePriority, Never>] = [:]

    /// The number of times each frame has been asked for, which is what tells
    /// a frame two players shared from one they each decoded.
    private(set) var decodeCounts: [Int: Int] = [:]

    /// The total number of decodes started.
    var decodeCount: Int { decodeCounts.values.reduce(0, +) }

    init(source: AnimatedImageSource, maxPixelSize: CGFloat? = nil) {
        self.decoder = AnimatedImageFrameDecoder(source: source, maxPixelSize: maxPixelSize)
    }

    func decode(at index: Int) async -> AnimatedImageFrameDecoder.Frame? {
        decodeCounts[index, default: 0] += 1
        recordPriority(Task.currentPriority, at: index)
        if released.remove(index) == nil {
            await withCheckedContinuation { gates[index] = $0 }
        }
        return await decoder.decode(at: index)
    }

    /// Lets the decode of the given frame finish, whether or not it has started.
    func release(_ index: Int) {
        if let gate = gates.removeValue(forKey: index) {
            gate.resume()
        } else {
            released.insert(index)
        }
    }

    /// The priority the decode of the given frame was started at, waiting for
    /// it to start if it hasn't yet.
    ///
    /// Read here rather than off the task the buffer holds, because awaiting a
    /// task escalates it to the priority of whatever is waiting – which is the
    /// one thing a test about priorities must not do.
    func priority(of index: Int) async -> DecodePriority {
        if let priority = startedPriorities[index] {
            return priority
        }
        return await withCheckedContinuation { priorityWaiters[index] = $0 }
    }

    private func recordPriority(_ priority: DecodePriority, at index: Int) {
        startedPriorities[index] = priority
        priorityWaiters.removeValue(forKey: index)?.resume(returning: priority)
    }
}

@MainActor
enum AnimatedImageTest {
    /// Builds a player driven by a clock the test owns.
    static func makePlayer(
        frameCount: Int = 4,
        delays: [TimeInterval]? = nil,
        loopCount: Int = 0,
        size: CGSize = CGSize(width: 8, height: 8),
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options(),
        pool: AnimatedImageFramePool = .shared
    ) -> (player: AnimatedImagePlayer, clock: ManualClock) {
        let data = Test.animatedGIF(frameCount: frameCount, delays: delays, loopCount: loopCount, size: size)
        let source = AnimatedImageSource(data: data)!
        let clock = ManualClock()
        let player = AnimatedImagePlayer(source: source, options: options, clock: clock, pool: pool)
        return (player, clock)
    }

    /// Builds a player whose decoder hands over one frame at a time.
    static func makeGatedPlayer(
        frameCount: Int = 8,
        delays: [TimeInterval]? = nil,
        size: CGSize = CGSize(width: 8, height: 8),
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options()
    ) -> (player: AnimatedImagePlayer, clock: ManualClock, decoder: GatedFrameDecoder) {
        let data = Test.animatedGIF(frameCount: frameCount, delays: delays, size: size)
        let source = AnimatedImageSource(data: data)!
        let clock = ManualClock()
        let decoder = GatedFrameDecoder(source: source)
        let player = AnimatedImagePlayer(source: source, options: options, clock: clock, decoder: decoder)
        return (player, clock, decoder)
    }

    /// The size of one decoded frame in memory.
    ///
    /// Read from a decoded frame rather than computed from the canvas size,
    /// because Core Graphics pads the rows of a bitmap for alignment.
    static func bytesPerFrame(of player: AnimatedImagePlayer) -> Int? {
        guard let cgImage = player.image?.cgImage else { return nil }
        return cgImage.bytesPerRow * cgImage.height
    }

    /// The color of the top-left pixel, which is what tells the generated
    /// frames apart.
    static func firstPixel(of image: PlatformImage?) -> [UInt8]? {
        guard let cgImage = image?.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = pixel.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
        guard let context else { return nil }
        // Draw the image scaled down to the single pixel of the context: every
        // generated frame is a solid color, so any pixel identifies the frame.
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel
    }
}
