// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// What ``AnimatedImageFrameTransform`` is handed, how often it runs, and what
/// its identifier does and doesn't share.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImageFrameTransformTests {
    /// A pool of its own for every test: which players share frames is what
    /// several of these assert, and the suite runs beside every other one.
    private let pool = AnimatedImageFramePool()

    // MARK: The Transformer

    @Test func doesNotRunTheTransformOnAFrameTheDecoderRefused() async {
        // A refused frame stays refused – the store remembers it and never
        // asks again – rather than being replaced by whatever a transform
        // makes of nothing.
        let log = TransformLog()
        let transformer = AnimatedImageFrameTransformer(
            decoder: RefusingDecoder(refused: [1]),
            transform: log.recording(identifier: "recording")
        )

        #expect(await transformer.decode(at: 1) == nil)
        #expect(log.count == 0)

        #expect(await transformer.decode(at: 0) != nil)
        #expect(log.count == 1)
    }

    // MARK: What It Is Handed

    @Test func isHandedTheFramesAtTheSizeTheyAreDecodedAt() async throws {
        // The transform works on the downsampled frames, not on full-size
        // ones it would then have to be scaled down from.
        let log = TransformLog()
        var options = AnimatedImagePlayer.Options()
        options.maxPixelSize = 16
        options.frameTransform = log.recording(identifier: "recording")
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 4, size: CGSize(width: 64, height: 32))))
        let player = makePlayer(source: source, options: options)

        await player.waitUntilFull()

        #expect(log.count == 4)
        #expect(log.sizes.allSatisfy { $0 == CGSize(width: 16, height: 8) })
    }

    @Test func transformsTheFramesOfADecoderOfYourOwn() async throws {
        // The two hooks compose: an animation that brings its own decoder is
        // transformed like any other.
        let made = AnimatedImageSource(
            data: Data(),
            delays: Array(repeating: 0.1, count: 4),
            size: CGSize(width: 8, height: 8),
            makeFrameDecoder: { _ in SolidColorFrameDecoder(id: "red", color: .red) }
        )
        let source = try #require(made)
        var options = AnimatedImagePlayer.Options()
        options.frameTransform = AnimatedImageFrameTransform(identifier: "blue") {
            SolidColor.blue.makeImage(size: CGSize(width: $0.width, height: $0.height))
        }

        let player = makePlayer(source: source, options: options)
        await player.waitUntilFull()

        #expect(AnimatedImageTest.firstPixel(of: player.image) == SolidColor.blue.pixel)
    }

    // MARK: How Often It Runs

    @Test func runsOncePerFrameForAnAnimationThatFits() async {
        let log = TransformLog()
        var options = AnimatedImagePlayer.Options()
        options.frameTransform = log.recording(identifier: "recording")
        let (player, clock) = makeTickingPlayer(frameCount: 4, options: options)
        player.play()
        await player.waitUntilFull()

        for _ in 0..<12 { // Three loops
            clock.tick(0.1)
            await player.waitUntilFull()
        }

        #expect(player.completedLoopCount == 3)
        #expect(log.count == 4)
    }

    @Test func runsAgainOnEveryLoopForAnAnimationThatDoesNot() async {
        // "Once per frame per loop": a window that slides decodes every frame
        // again each time round, and the transform with it.
        let log = TransformLog()
        var options = AnimatedImagePlayer.Options.twoFrameBuffer
        options.frameTransform = log.recording(identifier: "recording")
        let (player, clock) = makeTickingPlayer(frameCount: 4, options: options)
        player.play()
        await player.waitUntilFull()

        for _ in 0..<8 { // Two loops
            clock.tick(0.1)
            await player.waitUntilFull()
        }

        #expect(player.completedLoopCount == 2)
        #expect(log.count >= 2 * 4)
        #expect(player.diagnostics.decodedFrameCount == log.count)
    }

    // MARK: What It Costs

    @Test func costsWhatTheBitmapItReturnsOccupies() async throws {
        // A transform that draws into a larger bitmap of its own is charged
        // for that bitmap, not for the frame it was handed.
        let log = TransformLog()
        var options = AnimatedImagePlayer.Options()
        options.frameTransform = AnimatedImageFrameTransform(identifier: "doubled") { image in
            let doubled = SolidColor.red.makeImage(size: CGSize(width: image.width * 2, height: image.height * 2))
            log.record(doubled)
            return doubled
        }
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 4)))
        let player = makePlayer(source: source, options: options)

        await player.waitUntilFull()

        let bytes = try #require(log.byteCounts.first)
        #expect(log.byteCounts.allSatisfy { $0 == bytes })
        #expect(player.diagnostics.bufferedByteCount == 4 * bytes)
        #expect(pool.totalCost == 4 * bytes)
    }

    // MARK: Sharing

    @Test func anEmptyIdentifierIsStillATransform() async throws {
        // "" and no transform at all are two different sets of frames: the
        // untransformed player must not be handed transformed ones, or the
        // other way round.
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 4)))
        let plain = makePlayer(source: source)
        var options = AnimatedImagePlayer.Options()
        options.frameTransform = AnimatedImageFrameTransform(identifier: "") {
            SolidColor.blue.makeImage(size: CGSize(width: $0.width, height: $0.height))
        }
        let tinted = makePlayer(source: source, options: options)

        await plain.waitUntilFull()
        await tinted.waitUntilFull()

        #expect(pool.animationCount == 2)
        #expect(AnimatedImageTest.firstPixel(of: tinted.image) == SolidColor.blue.pixel)
        #expect(AnimatedImageTest.firstPixel(of: plain.image) != SolidColor.blue.pixel)
    }

    @Test func theIdentifierAndNotTheClosureDecidesWhatIsShared() async throws {
        // Two transforms with one identifier are taken at their word: the
        // frames are the ones the first of them produced. It is why the
        // identifier has to carry every parameter that changes the pixels.
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 4)))
        let red = makePlayer(source: source, options: makeOptions(identifier: "tint", color: .red))
        await red.waitUntilFull()

        let blue = makePlayer(source: source, options: makeOptions(identifier: "tint", color: .blue))
        await blue.waitUntilFull()

        #expect(pool.animationCount == 1)
        #expect(blue.diagnostics.decodedFrameCount == 0)
        let frame = try #require(blue.store.frame(at: 0))
        #expect(framePixel(of: frame) == SolidColor.red.pixel)
    }

    // MARK: Helpers

    private func makeOptions(identifier: String, color: SolidColor) -> AnimatedImagePlayer.Options {
        var options = AnimatedImagePlayer.Options()
        options.frameTransform = AnimatedImageFrameTransform(identifier: identifier) {
            color.makeImage(size: CGSize(width: $0.width, height: $0.height))
        }
        return options
    }

    /// A player that is playing, which is what makes it ask for every frame.
    private func makePlayer(
        source: AnimatedImageSource,
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options()
    ) -> AnimatedImagePlayer {
        let player = AnimatedImagePlayer(
            source: source,
            options: options,
            clock: ManualClock(),
            pool: pool,
            power: AnimatedImagePowerMonitor(isThrottling: false)
        )
        player.play()
        return player
    }

    private func makeTickingPlayer(frameCount: Int, options: AnimatedImagePlayer.Options) -> (player: AnimatedImagePlayer, clock: ManualClock) {
        AnimatedImageTest.makePlayer(frameCount: frameCount, options: options, pool: pool)
    }
}

/// Reads back a bitmap the way ``AnimatedImageTest/firstPixel(of:)`` reads
/// back what a player displays.
@MainActor
private func framePixel(of cgImage: CGImage) -> [UInt8]? {
#if canImport(UIKit)
    AnimatedImageTest.firstPixel(of: UIImage(cgImage: cgImage))
#else
    AnimatedImageTest.firstPixel(of: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
#endif
}

/// What a transform was handed, from whatever thread it ran on.
private final class TransformLog: @unchecked Sendable {
    private let lock = NSLock()
    private var handed: [CGSize] = []
    private var produced: [Int] = []

    var count: Int { lock.withLock { handed.count } }
    var sizes: [CGSize] { lock.withLock { handed } }

    /// The memory each image the transform returned occupies.
    var byteCounts: [Int] { lock.withLock { produced } }

    func record(_ output: CGImage) {
        lock.withLock { produced.append(output.bytesPerRow * output.height) }
    }

    /// A transform that leaves the frames alone and writes down what it saw.
    func recording(identifier: String) -> AnimatedImageFrameTransform {
        AnimatedImageFrameTransform(identifier: identifier) { [self] image in
            lock.withLock { handed.append(CGSize(width: image.width, height: image.height)) }
            return image
        }
    }
}

/// Produces a solid frame for every index but the ones it is told to refuse.
private struct RefusingDecoder: AnimatedImageFrameDecoding {
    let refused: Set<Int>

    func decode(at index: Int) async -> CGImage? {
        refused.contains(index) ? nil : SolidColor.red.makeImage(size: CGSize(width: 8, height: 8))
    }
}
