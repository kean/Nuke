// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

/// The two ways the frames of an animation can be produced by something other
/// than Image I/O drawing the container: a decoder carried by the animation
/// itself, and a transform applied to every frame as it is decoded.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImageFrameDecodingTests: AnimatedImagePoolSuite {
    let pool = AnimatedImageFramePool()

    // MARK: Custom Decoders

    @Test func playsTheFramesTheAnimationsOwnDecoderProduces() async throws {
        let player = try makeIdlePlayer(source: makeCustomSource(color: .red)).player

        await player.waitUntilFull()

        #expect(Test.firstPixel(of: player.image) == SolidColor.red.pixel)
    }

    @Test func decodesWithImageIOWhenTheAnimationCarriesNoDecoder() throws {
        let source = Test.animatedGIFSource()

        #expect(source.makeFrameDecoder() is AnimatedImageFrameDecoder)
    }

    @Test func playsAFormatImageIOCannotRead() async throws {
        // The case the whole hook exists for. Image I/O can't open the
        // container, so the animation is described by the decoder that can.
        let data = Flipbook.encode(frameCount: 4)
        #expect(AnimatedImageSource(data: data) == nil)
        let flipbook = try #require(Flipbook(data: data))
        let made = AnimatedImageSource(
            data: data,
            delays: flipbook.delays,
            size: flipbook.size,
            makeFrameDecoder: { FlipbookFrameDecoder(flipbook, maxPixelSize: $0) }
        )
        let source = try #require(made)

        let (player, clock) = makeIdlePlayer(source: source)
        player.play()
        await player.waitUntilFull()

        #expect(player.source.frameCount == 4)
        #expect(Test.firstPixel(of: player.image) == flipbook.frames[0].pixel)

        // And it goes on playing: the frames are windowed and handed over on
        // the clock exactly as Image I/O's are.
        clock.tick(0.1)
        #expect(player.currentFrameIndex == 1)
        #expect(Test.firstPixel(of: player.image) == flipbook.frames[1].pixel)
    }

    @Test func handsTheDecoderTheSizeTheFramesAreWantedAt() async throws {
        // What the player budgeted memory for, so a decoder is expected to
        // honor it.
        let sizes = LockedArray<CGFloat?>()
        let made = AnimatedImageSource(
            data: Data(),
            delays: Array(repeating: 0.1, count: 4),
            size: CGSize(width: 64, height: 64),
            makeFrameDecoder: { maxPixelSize in
                sizes.append(maxPixelSize)
                return SolidColorFrameDecoder(id: "red", color: .red)
            }
        )
        let source = try #require(made)
        var options = AnimatedImagePlayer.Options()
        options.maxPixelSize = 16

        let player = makeIdlePlayer(source: source, options: options).player
        await player.waitUntilFull()

        #expect(sizes.values == [16])
    }

    @Test func makesOneDecoderForEveryPlayerOfAnAnimation() async throws {
        // The frames of one animation at one size are decoded once and shared,
        // so the factory is asked once however many views show it.
        let sizes = LockedArray<CGFloat?>()
        let made = AnimatedImageSource(
            data: Data(),
            delays: Array(repeating: 0.1, count: 4),
            size: CGSize(width: 8, height: 8),
            makeFrameDecoder: { maxPixelSize in
                sizes.append(maxPixelSize)
                return SolidColorFrameDecoder(id: "red", color: .red)
            }
        )
        let source = try #require(made)

        let first = makeIdlePlayer(source: source).player
        await first.waitUntilFull()
        let second = makeIdlePlayer(source: source).player
        await second.waitUntilFull()

        #expect(sizes.values == [nil])
        #expect(second.diagnostics.decodedFrameCount == 0)
    }

    // MARK: Per-Frame Transform

    @Test func appliesTheTransformToEveryFrame() async throws {
        let (player, clock) = makeIdlePlayer(source: Test.animatedGIFSource(), options: makeOptions(transform: .red))
        player.play()

        await player.waitUntilFull()
        #expect(Test.firstPixel(of: player.image) == SolidColor.red.pixel)

        // The frame after it, which the decoder produced separately, and not
        // the color the fixture wrote for it.
        clock.tick(0.1)
        #expect(player.currentFrameIndex == 1)
        #expect(Test.firstPixel(of: player.image) == SolidColor.red.pixel)
    }

    @Test func runsTheTransformOffTheMainActor() async throws {
        // The point of the hook: whatever it does to a frame is not done on
        // the thread the animation is displayed on.
        let recorder = LockedArray<Bool>()
        var options = AnimatedImagePlayer.Options()
        options.frameTransform = AnimatedImageFrameTransform(identifier: "recording") { image in
            recorder.append(Thread.isMainThread)
            return image
        }
        let player = makeIdlePlayer(source: Test.animatedGIFSource(), options: options).player

        await player.waitUntilFull()

        #expect(recorder.values.isEmpty == false)
        #expect(recorder.values.allSatisfy { $0 == false })
    }

    @Test func keepsTheDecodedFrameWhenTheTransformReturnsNil() async throws {
        var options = AnimatedImagePlayer.Options()
        options.frameTransform = AnimatedImageFrameTransform(identifier: "declining") { _ in nil }
        let player = makeIdlePlayer(source: Test.animatedGIFSource(), options: options).player
        let untransformed = makeIdlePlayer(source: Test.animatedGIFSource(), pool: AnimatedImageFramePool()).player

        await player.waitUntilFull()
        await untransformed.waitUntilFull()

        #expect(Test.firstPixel(of: player.image) == Test.firstPixel(of: untransformed.image))
    }

    @Test func countsTheTransformAsPartOfWhatAFrameCostsToProduce() async throws {
        let player = makeIdlePlayer(source: Test.animatedGIFSource(), options: makeOptions(transform: .red)).player

        await player.waitUntilFull()

        #expect(player.diagnostics.decodedFrameCount > 0)
        #expect(player.diagnostics.lastDecodeDuration > 0)
    }

    // MARK: Sharing the Transformed Frames

    @Test func playersWithTheSameTransformShareFrames() async throws {
        let source = Test.animatedGIFSource()
        let first = makeIdlePlayer(source: source, options: makeOptions(transform: .red)).player
        await first.waitUntilFull()

        let second = makeIdlePlayer(source: source, options: makeOptions(transform: .red)).player

        #expect(pool.animationCount == 1)
        #expect(second.diagnostics.decodedFrameCount == 0)
        #expect(second.store.frame(at: 0) === first.store.frame(at: 0))
    }

    @Test func playersWithDifferentTransformsDoNotShareFrames() async throws {
        // Two views drawing the same animation differently must not be handed
        // each other's frames.
        let source = Test.animatedGIFSource()
        let red = makeIdlePlayer(source: source, options: makeOptions(transform: .red)).player
        let blue = makeIdlePlayer(source: source, options: makeOptions(transform: .blue)).player

        await red.waitUntilFull()
        await blue.waitUntilFull()

        #expect(pool.animationCount == 2)
        #expect(Test.firstPixel(of: red.image) == SolidColor.red.pixel)
        #expect(Test.firstPixel(of: blue.image) == SolidColor.blue.pixel)
    }

    @Test func aTransformedPlayerDoesNotShareWithAnUntransformedOne() async throws {
        let source = Test.animatedGIFSource()
        _ = makeIdlePlayer(source: source)
        _ = makeIdlePlayer(source: source, options: makeOptions(transform: .red))

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

    /// A GIF that describes itself but draws itself in a solid color, which is
    /// what tells the frames of a decoder of your own from Image I/O's.
    private func makeCustomSource(color: SolidColor, frameCount: Int = 4) throws -> AnimatedImageSource {
        let source = AnimatedImageSource(
            data: Test.animatedGIF(frameCount: frameCount),
            delays: Array(repeating: 0.1, count: frameCount),
            size: CGSize(width: 8, height: 8),
            makeFrameDecoder: { _ in SolidColorFrameDecoder(id: color.rawValue, color: color) }
        )
        return try #require(source)
    }
}

/// The colors these tests build frames out of, and the pixel each one reads
/// back as through ``Test/firstPixel(of:)``.
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

    func decode(at index: Int) async -> CGImage? {
        color.makeImage(size: size)
    }
}
