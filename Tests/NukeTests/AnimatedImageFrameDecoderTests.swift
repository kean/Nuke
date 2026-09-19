// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Nuke

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The decoder every animation gets unless it carries one of its own: Image
/// I/O composing, scaling, and decompressing one frame at a time.
@Suite(.timeLimit(.minutes(1)))
struct AnimatedImageFrameDecoderTests {

    // MARK: Composition

    @Test func composesTheFramesThatRedrawOnlyPartOfTheCanvas() async throws {
        // Most of `cat.gif` is stored as sub-rects – frame 3 is `14,4` to
        // `495,279` – so a decoder that hands back what the container stores
        // instead of what it composes onto the canvas is caught here, and
        // nowhere else: every generated fixture writes whole frames.
        let source = try #require(AnimatedImageSource(data: Test.data(name: "cat", extension: "gif")))
        let decoder = AnimatedImageFrameDecoder(source: source)
        let composing = try #require(source.makeImageSource())

        for index in [0, 1, 3, 8, source.frameCount - 1] {
            let frame = try #require(await decoder.decode(at: index))
            let composed = try #require(CGImageSourceCreateImageAtIndex(composing, index, AnimatedImageSource.imageSourceOptions))
            #expect(frame.width == composed.width)
            #expect(frame.height == composed.height)
            #expect(maxDifference(frame, composed) <= 1)
        }
    }

    @Test func composesTheFramesItIsAskedForOutOfOrder() async throws {
        // A seek asks for a frame the playhead skipped to, and the disposal of
        // a GIF is defined by the frames before it.
        let source = try #require(AnimatedImageSource(data: Test.data(name: "cat", extension: "gif")))
        let composing = try #require(source.makeImageSource())
        var reference: [Int: CGImage] = [:]
        for index in 0..<source.frameCount {
            reference[index] = CGImageSourceCreateImageAtIndex(composing, index, AnimatedImageSource.imageSourceOptions)
        }

        let decoder = AnimatedImageFrameDecoder(source: source)
        for index in [7, 2, 21, 0, 14, 3] {
            let frame = try #require(await decoder.decode(at: index))
            #expect(maxDifference(frame, try #require(reference[index])) <= 1)
        }
    }

    // MARK: Size

    @Test func decodesAtTheSizeTheAnimationIsStoredAtWhenThereIsNoLimit() async throws {
        let source = try #require(AnimatedImageSource(data: Test.data(name: "cat", extension: "gif")))

        let frame = try #require(await AnimatedImageFrameDecoder(source: source).decode(at: 0))

        #expect(CGSize(width: frame.width, height: frame.height) == source.size)
    }

    @Test func scalesTheFramesDownToTheLimit() async throws {
        let source = try #require(AnimatedImageSource(data: Test.data(name: "cat", extension: "gif")))

        let frame = try #require(await AnimatedImageFrameDecoder(source: source, maxPixelSize: 100).decode(at: 0))

        // The longest side reaches the limit and the aspect ratio survives:
        // 500 x 279 scaled by 100/500.
        #expect(frame.width == 100)
        #expect(frame.height == 56)
    }

    @Test func neverEnlargesAFrameToReachTheLimit() async throws {
        let source = try #require(AnimatedImageSource(data: Test.data(name: "cat", extension: "gif")))

        let frame = try #require(await AnimatedImageFrameDecoder(source: source, maxPixelSize: 4000).decode(at: 0))

        #expect(CGSize(width: frame.width, height: frame.height) == source.size)
    }

    @Test(arguments: ["gif", "heics"] as [String])
    func producesAFrameForALimitNoThumbnailCanMeet(format: String) async throws {
        // Image I/O declines a limit some codecs can't scale to – HEICS
        // answers a single pixel with nothing where GIF returns one – and the
        // frame is decoded whole and drawn instead, so playback goes on.
        let data = try #require(format == "gif" ? Test.animatedGIF(size: CGSize(width: 64, height: 64))
                                                : Test.animatedHEICS(size: CGSize(width: 64, height: 64)))
        let source = try #require(AnimatedImageSource(data: data))

        let frame = try #require(await AnimatedImageFrameDecoder(source: source, maxPixelSize: 1).decode(at: 0))

        #expect(max(frame.width, frame.height) == 1)
    }

    // MARK: Orientation

    @Test(arguments: orientations)
    func decodesTheFramesWithTheOrientationTheContainerDeclares(orientation: CGImagePropertyOrientation) async throws {
        // A rotated animated WebP or HEIC declares one, and Image I/O hands
        // the pixels over the way the container stores them unless it is asked
        // to apply it – so this is what keeps a rotated animation upright.
        guard let data = Test.animatedPNG(frameCount: 3, size: CGSize(width: 24, height: 12), orientation: orientation) else {
            return // Image I/O on this platform can't write an APNG
        }
        let source = try #require(AnimatedImageSource(data: data))
        let reference = try #require(orientedFrame(at: 1, in: data))

        let frame = try #require(await AnimatedImageFrameDecoder(source: source).decode(at: 1))

        #expect(CGSize(width: frame.width, height: frame.height) == source.size)
        #expect(maxDifference(frame, reference) <= 1)
    }

    @Test(arguments: orientations)
    func appliesTheOrientationToAFrameItDecodesByDrawing(orientation: CGImagePropertyOrientation) throws {
        // The other half of it: the fallback draws the frame Image I/O hands
        // over whole, and that one carries no orientation either, so the draw
        // is what has to apply it.
        guard let data = Test.animatedPNG(frameCount: 3, size: CGSize(width: 24, height: 12), orientation: orientation) else {
            return // Image I/O on this platform can't write an APNG
        }
        let container = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let stored = try #require(CGImageSourceCreateImageAtIndex(container, 1, nil))
        let reference = try #require(orientedFrame(at: 1, in: data))

        let frame = try #require(stored.drawn(inCanvasWithSize: stored.size, orientation: orientation))

        #expect(frame.width == reference.width)
        #expect(frame.height == reference.height)
        #expect(maxDifference(frame, reference) <= 1)
    }

    @Test func decodesTheFramesTheWayTheStillBesideThemIsDecoded() async throws {
        // The two halves the view puts on screen one after the other: the
        // still the pipeline decodes with `UIImage(data:)`, which applies the
        // orientation, and the frames that replace it the moment playback
        // starts.
        guard let data = Test.animatedPNG(size: CGSize(width: 24, height: 12), orientation: .right) else {
            return // Image I/O on this platform can't write an APNG
        }
        let container = try ImageDecoders.Default().decode(data)
        let source = try #require(container.animation)

        let frame = try #require(await AnimatedImageFrameDecoder(source: source).decode(at: 0))

        #expect(container.image.size == CGSize(width: 12, height: 24))
        #expect(CGSize(width: frame.width, height: frame.height) == container.image.size)
    }

    /// The frame Image I/O produces when it is the one applying the
    /// orientation, which is what a correctly decoded frame has to match.
    ///
    /// The limit is the longest side of the fixtures here, so nothing is
    /// scaled: what is being compared is the orientation, not the resampling.
    private func orientedFrame(at index: Int, in data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 24
        ] as CFDictionary)
    }

    // MARK: Decompression

    @Test func handsBackFramesThatAreAlreadyDecompressed() async throws {
        // Image I/O returns a *lazy* image from a thumbnail request that
        // carries no size limit, and decompresses it the first time something
        // draws it – which is the main thread. Nothing about such a frame
        // looks wrong; only when it is drawn does the cost appear, so this is
        // pinned by where the time goes rather than by what the frame is.
        let source = try #require(AnimatedImageSource(data: Test.data(name: "cat", extension: "gif")))
        let decoder = AnimatedImageFrameDecoder(source: source)
        let canvas = try #require(CGContext(
            data: nil,
            width: Int(source.size.width),
            height: Int(source.size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ))

        var decoding: TimeInterval = 0
        var drawing: TimeInterval = 0
        for index in 0..<source.frameCount {
            let started = Date()
            let frame = try #require(await decoder.decode(at: index))
            let decoded = Date()
            canvas.draw(frame, in: CGRect(origin: .zero, size: source.size))
            decoding += decoded.timeIntervalSince(started)
            drawing += Date().timeIntervalSince(decoded)
        }

        // A decompressed frame draws in a fraction of what it took to produce;
        // a lazy one costs more to draw than it did to "decode", because the
        // decode is what the draw is doing. The two are an order of magnitude
        // apart, so the margin here is generous on purpose.
        #expect(drawing * 2 < decoding)
    }
}

/// Every orientation a container can declare, in the order EXIF numbers them.
private let orientations: [CGImagePropertyOrientation] = [
    .up, .upMirrored, .down, .downMirrored, .leftMirrored, .right, .rightMirrored, .left
]

/// The largest per-component difference between two images, compared through a
/// grid small enough that the sampling itself is what normalizes the pixel
/// layout and the color space the two were decoded into.
private func maxDifference(_ lhs: CGImage, _ rhs: CGImage, grid: Int = 24) -> Int {
    let samples = [lhs, rhs].map { image -> [UInt8] in
        let context = CGContext(
            data: nil,
            width: grid,
            height: grid,
            bitsPerComponent: 8,
            bytesPerRow: grid * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: grid, height: grid))
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: grid * grid * 4)
        return Array(UnsafeBufferPointer(start: pixels, count: grid * grid * 4))
    }
    return zip(samples[0], samples[1]).map { abs(Int($0) - Int($1)) }.max() ?? 0
}
