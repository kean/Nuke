// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

/// The two ways the frames of an animation can be produced by something other
/// than Image I/O drawing the container: a decoder of your own, and a
/// transform applied to every frame as it is decoded.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImageFrameDecodingTests {
    /// A pool of its own for every test: what a player holds depends on what
    /// every other animation on screen is asking for, and the suite runs
    /// beside every other one.
    private let pool = AnimatedImageFramePool()

    /// A registry of its own for the same reason: the shared one is process
    /// wide, and a test must not register a decoder into another test's run.
    private let registry = AnimatedImageFrameDecoderRegistry()

    // MARK: Custom Decoders

    @Test func playsTheFramesTheRegisteredDecoderProduces() async throws {
        registry.register { _ in SolidColorFrameDecoder(id: "red", color: .red) }
        let player = try makePlayer()

        await player.waitUntilFull()

        #expect(AnimatedImageTest.firstPixel(of: player.image) == SolidColor.red.pixel)
    }

    @Test func fallsBackToImageIOWhenNoDecoderMatches() async throws {
        // A registration that passes on every animation is the same as none.
        registry.register { _ in nil }
        let player = try makePlayer()
        let imageIO = try makePlayer(pool: AnimatedImageFramePool())

        await player.waitUntilFull()
        await imageIO.waitUntilFull()

        #expect(AnimatedImageTest.firstPixel(of: player.image) == AnimatedImageTest.firstPixel(of: imageIO.image))
    }

    @Test func asksTheMostRecentlyRegisteredDecoderFirst() throws {
        let context = try makeContext()
        registry.register { _ in SolidColorFrameDecoder(id: "first", color: .red) }
        let second = registry.register { _ in SolidColorFrameDecoder(id: "second", color: .blue) }

        #expect(identifier(of: registry.decoder(for: context)) == "second")

        // Unregistering falls back to the one under it, and clearing the
        // registry falls back to Image I/O.
        registry.unregister(second)
        #expect(identifier(of: registry.decoder(for: context)) == "first")
        registry.clear()
        #expect(registry.decoder(for: context) is AnimatedImageFrameDecoder)
    }

    @Test func answersWithImageIOWhenNothingIsRegistered() throws {
        #expect(try registry.decoder(for: makeContext()) is AnimatedImageFrameDecoder)
    }

    @Test func computesTheFrameSizeFromTheBitmap() {
        let image = SolidColor.red.makeImage(size: CGSize(width: 8, height: 8))
        let frame = AnimatedImageFrame(image: image)

        #expect(frame.byteCount == image.bytesPerRow * image.height)
        #expect(frame.decodeDuration == 0)
    }

    // MARK: Per-Frame Transform

    @Test func appliesTheTransformToEveryFrame() async throws {
        let (player, clock) = try makeIdlePlayer(options: makeOptions(transform: .red))
        player.play()

        await player.waitUntilFull()
        #expect(AnimatedImageTest.firstPixel(of: player.image) == SolidColor.red.pixel)

        // The frame after it, which the decoder produced separately, and not
        // the color the fixture wrote for it.
        clock.tick(0.1)
        #expect(player.currentFrameIndex == 1)
        #expect(AnimatedImageTest.firstPixel(of: player.image) == SolidColor.red.pixel)
    }

    @Test func runsTheTransformOffTheMainActor() async throws {
        // The point of the hook: whatever it does to a frame is not done on
        // the thread the animation is displayed on.
        let recorder = Recorder()
        var options = AnimatedImagePlayer.Options()
        options.frameTransform = AnimatedImageFrameTransform(identifier: "recording") { image in
            recorder.record(Thread.isMainThread)
            return image
        }
        let player = try makePlayer(options: options)

        await player.waitUntilFull()

        #expect(recorder.values.isEmpty == false)
        #expect(recorder.values.allSatisfy { $0 == false })
    }

    @Test func keepsTheDecodedFrameWhenTheTransformReturnsNil() async throws {
        var options = AnimatedImagePlayer.Options()
        options.frameTransform = AnimatedImageFrameTransform(identifier: "declining") { _ in nil }
        let player = try makePlayer(options: options)
        let untransformed = try makePlayer(pool: AnimatedImageFramePool())

        await player.waitUntilFull()
        await untransformed.waitUntilFull()

        #expect(AnimatedImageTest.firstPixel(of: player.image) == AnimatedImageTest.firstPixel(of: untransformed.image))
    }

    @Test func countsTheTransformAsPartOfWhatAFrameCostsToProduce() async throws {
        let player = try makePlayer(options: makeOptions(transform: .red))

        await player.waitUntilFull()

        #expect(player.diagnostics.decodedFrameCount > 0)
        #expect(player.diagnostics.lastDecodeDuration > 0)
    }

    // MARK: Sharing the Transformed Frames

    @Test func playersWithTheSameTransformShareFrames() async throws {
        let source = try makeSource()
        let first = try makePlayer(source: source, options: makeOptions(transform: .red))
        await first.waitUntilFull()

        let second = try makePlayer(source: source, options: makeOptions(transform: .red))

        #expect(pool.animationCount == 1)
        #expect(second.diagnostics.decodedFrameCount == 0)
        #expect(second.store.frame(at: 0) === first.store.frame(at: 0))
    }

    @Test func playersWithDifferentTransformsDoNotShareFrames() async throws {
        // Two views drawing the same animation differently must not be handed
        // each other's frames.
        let source = try makeSource()
        let red = try makePlayer(source: source, options: makeOptions(transform: .red))
        let blue = try makePlayer(source: source, options: makeOptions(transform: .blue))

        await red.waitUntilFull()
        await blue.waitUntilFull()

        #expect(pool.animationCount == 2)
        #expect(AnimatedImageTest.firstPixel(of: red.image) == SolidColor.red.pixel)
        #expect(AnimatedImageTest.firstPixel(of: blue.image) == SolidColor.blue.pixel)
    }

    @Test func aTransformedPlayerDoesNotShareWithAnUntransformedOne() async throws {
        let source = try makeSource()
        _ = try makePlayer(source: source)
        _ = try makePlayer(source: source, options: makeOptions(transform: .red))

        #expect(pool.animationCount == 2)
    }

    // MARK: Helpers

    private func makeOptions(transform color: SolidColor) -> AnimatedImagePlayer.Options {
        var options = AnimatedImagePlayer.Options()
        options.frameTransform = AnimatedImageFrameTransform(identifier: color.rawValue) { image in
            color.makeImage(size: CGSize(width: image.width, height: image.height))
        }
        return options
    }

    private func makePlayer(
        source: AnimatedImageSource? = nil,
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options(),
        pool: AnimatedImageFramePool? = nil
    ) throws -> AnimatedImagePlayer {
        try makeIdlePlayer(source: source, options: options, pool: pool).player
    }

    private func makeIdlePlayer(
        source: AnimatedImageSource? = nil,
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options(),
        pool: AnimatedImageFramePool? = nil
    ) throws -> (player: AnimatedImagePlayer, clock: ManualClock) {
        let pool = pool ?? self.pool
        pool.decoderRegistry = registry
        let clock = ManualClock()
        let player = try AnimatedImagePlayer(
            source: source ?? makeSource(),
            options: options,
            clock: clock,
            pool: pool
        )
        return (player, clock)
    }

    private func makeSource(frameCount: Int = 4) throws -> AnimatedImageSource {
        try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: frameCount)))
    }

    private func makeContext() throws -> AnimatedImageFrameDecodingContext {
        try AnimatedImageFrameDecodingContext(source: makeSource())
    }

    private func identifier(of decoder: any AnimatedImageFrameDecoding) -> String? {
        (decoder as? SolidColorFrameDecoder)?.id
    }
}

/// The colors these tests build frames out of, and the pixel each one reads
/// back as through ``AnimatedImageTest/firstPixel(of:)``.
enum SolidColor: String {
    case red, blue

    var pixel: [UInt8] {
        switch self {
        case .red: [255, 0, 0, 255]
        case .blue: [0, 0, 255, 255]
        }
    }

    var components: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        switch self {
        case .red: (1, 0, 0)
        case .blue: (0, 0, 1)
        }
    }

    /// Draws a solid image of this color.
    func makeImage(size: CGSize) -> CGImage {
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let components = components
        context.setFillColor(red: components.red, green: components.green, blue: components.blue, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        return context.makeImage()!
    }
}

/// A decoder that answers with a solid color instead of decoding anything,
/// which is what tells its frames from the ones Image I/O produces.
struct SolidColorFrameDecoder: AnimatedImageFrameDecoding {
    let id: String
    let color: SolidColor
    var size = CGSize(width: 8, height: 8)

    func decode(at index: Int) async -> AnimatedImageFrame? {
        AnimatedImageFrame(image: color.makeImage(size: size))
    }
}

/// Collects what a transform saw, from whatever thread it ran on.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Bool] = []

    var values: [Bool] {
        lock.withLock { storage }
    }

    func record(_ value: Bool) {
        lock.withLock { storage.append(value) }
    }
}
