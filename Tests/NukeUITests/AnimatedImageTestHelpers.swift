// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
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

    /// What a tick that arrives on time is worth: a 60 Hz display unless a
    /// test says otherwise.
    var period: TimeInterval = 1.0 / 60

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

/// A decoder that produces a frame only once the test releases it, and that
/// refuses the frames it is told to, the way one reading a truncated
/// animation does.
///
/// A player that outruns its decoder is otherwise a race: the test would have
/// to make the frames big enough to decode slowly and hope they stay slow.
actor GatedFrameDecoder: AnimatedImageFrameDecoding {
    private let decoder: AnimatedImageFrameDecoder
    private let refused: Set<Int>
    private let isGated: Bool
    private var gates: [Int: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<Int> = []
    private var startedPriorities: [Int: DecodePriority] = [:]
    private var priorityWaiters: [Int: CheckedContinuation<DecodePriority, Never>] = [:]

    /// The number of times each frame has been asked for, which is what tells
    /// a frame two players shared from one they each decoded.
    private(set) var decodeCounts: [Int: Int] = [:]

    /// The total number of decodes started.
    var decodeCount: Int { decodeCounts.values.reduce(0, +) }

    /// The frames the decoder was asked for, in the order it was asked, which
    /// is what tells read-ahead in playback order from any other order.
    private(set) var startedIndexes: [Int] = []

    /// - parameter refused: The frames it answers with no image.
    /// - parameter isGated: `false` for a decoder that hands over every frame
    ///   as soon as it is asked for it.
    init(source: AnimatedImageSource, maxPixelSize: CGFloat? = nil, refusing refused: Set<Int> = [], isGated: Bool = true) {
        self.decoder = AnimatedImageFrameDecoder(source: source, maxPixelSize: maxPixelSize)
        self.refused = refused
        self.isGated = isGated
    }

    func decode(at index: Int) async -> CGImage? {
        decodeCounts[index, default: 0] += 1
        startedIndexes.append(index)
        recordPriority(Task.currentPriority, at: index)
        if isGated, released.remove(index) == nil {
            await withCheckedContinuation { gates[index] = $0 }
        }
        guard !refused.contains(index) else {
            return nil
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
    /// Builds a player of the given animation, driven by a clock the test owns.
    ///
    /// Nothing starts it: a player that isn't playing asks for the first two
    /// frames only, and `play()` is what makes it ask for a full window.
    ///
    /// - parameter pool: A pool of the player's own unless the test passes
    ///   one: what a player is allowed to hold depends on what every other
    ///   animation in its pool is asking for, and the suites run beside each
    ///   other.
    /// - parameter decoder: A decoder to use in place of the animation's own.
    static func makePlayer(
        source: AnimatedImageSource,
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options(),
        pool: AnimatedImageFramePool = AnimatedImageFramePool(),
        decoder: (any AnimatedImageFrameDecoding)? = nil,
        power: AnimatedImagePowerMonitor = AnimatedImagePowerMonitor(isThrottling: false)
    ) -> (player: AnimatedImagePlayer, clock: ManualClock) {
        let clock = ManualClock()
        let player = AnimatedImagePlayer(source: source, options: options, clock: clock, pool: pool, power: power, decoder: decoder)
        return (player, clock)
    }

    /// Builds a player of a generated GIF, driven by a clock the test owns.
    static func makePlayer(
        frameCount: Int = 4,
        delays: [TimeInterval]? = nil,
        loopCount: Int = 0,
        size: CGSize = CGSize(width: 8, height: 8),
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options(),
        pool: AnimatedImageFramePool = AnimatedImageFramePool(),
        power: AnimatedImagePowerMonitor = AnimatedImagePowerMonitor(isThrottling: false)
    ) -> (player: AnimatedImagePlayer, clock: ManualClock) {
        let source = Test.animatedGIFSource(frameCount: frameCount, delays: delays, loopCount: loopCount, size: size)
        return makePlayer(source: source, options: options, pool: pool, power: power)
    }

    /// Builds a player whose decoder hands over one frame at a time.
    static func makeGatedPlayer(
        frameCount: Int = 8,
        delays: [TimeInterval]? = nil,
        size: CGSize = CGSize(width: 8, height: 8),
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options()
    ) -> (player: AnimatedImagePlayer, clock: ManualClock, decoder: GatedFrameDecoder) {
        let source = Test.animatedGIFSource(frameCount: frameCount, delays: delays, size: size)
        let decoder = GatedFrameDecoder(source: source)
        let (player, clock) = makePlayer(source: source, options: options, decoder: decoder)
        return (player, clock, decoder)
    }

    /// Releases the frame and waits for the decode in flight – the one the
    /// frame is waiting on – to hand it over.
    ///
    /// The decode is read before the frame is released: the next one starts
    /// as soon as it finishes.
    static func decode(
        _ index: Int,
        of player: AnimatedImagePlayer,
        with decoder: GatedFrameDecoder,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let decode = try #require(player.store.currentDecode, sourceLocation: sourceLocation)
        await decoder.release(index)
        await decode.value
    }

    /// The size of one decoded frame in memory.
    ///
    /// Read from a decoded frame rather than computed from the canvas size,
    /// because Core Graphics pads the rows of a bitmap for alignment.
    static func bytesPerFrame(of player: AnimatedImagePlayer) -> Int? {
        guard let cgImage = player.image?.cgImage else { return nil }
        return cgImage.bytesPerRow * cgImage.height
    }
}

/// A suite whose tests each hold the frames of their players in a pool of
/// their own.
///
/// What a player is allowed to hold depends on what every other animation in
/// its pool is asking for, and the suites run beside each other. Swift Testing
/// creates the suite anew for every test, so its pool is the test's own, and
/// the players one test builds share it the way the players on one screen do.
@MainActor
protocol AnimatedImagePoolSuite {
    var pool: AnimatedImageFramePool { get }
}

extension AnimatedImagePoolSuite {
    /// A player that is playing, which is what makes it ask for a full window
    /// of frames. One that isn't asks for two.
    ///
    /// - parameter pool: The pool to hold the frames in, if not the test's.
    func makePlayer(
        source: AnimatedImageSource,
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options(),
        pool: AnimatedImageFramePool? = nil,
        decoder: (any AnimatedImageFrameDecoding)? = nil
    ) -> AnimatedImagePlayer {
        let player = makeIdlePlayer(source: source, options: options, pool: pool, decoder: decoder).player
        player.play()
        return player
    }

    /// A player nothing has started, on a clock the test drives.
    ///
    /// - parameter pool: The pool to hold the frames in, if not the test's.
    func makeIdlePlayer(
        source: AnimatedImageSource,
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options(),
        pool: AnimatedImageFramePool? = nil,
        decoder: (any AnimatedImageFrameDecoding)? = nil
    ) -> (player: AnimatedImagePlayer, clock: ManualClock) {
        AnimatedImageTest.makePlayer(source: source, options: options, pool: pool ?? self.pool, decoder: decoder)
    }
}
