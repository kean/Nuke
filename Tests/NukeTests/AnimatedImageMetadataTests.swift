// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Nuke

/// The metadata ``AnimatedImageSource`` reads out of a container – and the
/// metadata it has to make up when the container has none, or lies.
@Suite(.timeLimit(.minutes(5)))
struct AnimatedImageMetadataTests {

    // MARK: Missing Metadata

    @Test func aGIFWithNoMetadataAtAllPlaysOnceAtTheDefaultDelay() throws {
        // Two frames and nothing else: no graphic control extension, so no
        // delay, and no Netscape extension, so no loop count. Image I/O
        // publishes no per-frame dictionary for such a frame at all.
        let data = makeGIFWithoutExtensions(frameCount: 2)
        let imageSource = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let frame = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        #expect(frame?[kCGImagePropertyGIFDictionary] == nil)

        // When
        let source = try #require(AnimatedImageSource(data: data))

        // Then
        #expect(source.frameCount == 2)
        #expect(source.delays == [AnimatedImageSource.defaultDelay, AnimatedImageSource.defaultDelay])
        #expect(abs(source.duration - 0.2) < 0.0001)
        #expect(source.loopCount == 1)
        #expect(source.size == CGSize(width: 1, height: 1))
    }

    @Test func animationWithAnEmptyCanvasHasNothingToDecode() async throws {
        // A logical screen of 0×0: Image I/O counts the frames and publishes
        // the container dictionary, but reports no dimensions for a frame and
        // can't decode one.
        let data = makeGIFWithoutExtensions(frameCount: 2, screenSize: 0)

        let source = try #require(AnimatedImageSource(data: data))

        #expect(source.frameCount == 2)
        #expect(source.size == .zero)
        #expect(source.bytesPerFrame == 0)
        // No canvas and no limit: the one case with no size to ask for, and
        // no frame to draw either.
        #expect(await source.makeFrameDecoder().decode(at: 0) == nil)
        #expect(await source.makeFrameDecoder(maxPixelSize: 8).decode(at: 1) == nil)
    }

    @Test func zeroDelaysPlayAtTheDefault() throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 3, delays: [0, 0, 0.3])))
        #expect(source.delays == [0.1, 0.1, 0.3])
    }

    @Test func frameImageIOReportsNothingForGetsTheDefaultDelay() throws {
        let imageSource = try #require(CGImageSourceCreateWithData(Test.animatedGIF(frameCount: 2) as CFData, nil))

        #expect(AnimatedImageFormat.gif.delay(in: imageSource, at: 99) == AnimatedImageSource.defaultDelay)
    }

    // MARK: Delays

    @Test func apngDelaysAreReadUnclamped() throws {
        // APNG stores delays as fractions, fine enough to go under the 0.05 s
        // Image I/O clamps the fast frames up to in the key it calls
        // `DelayTime`. Reading that one would play all three of the fast
        // frames at 0.05 s.
        guard let data = Test.animatedPNG(frameCount: 4, delays: [0.005, 0.013, 0.02, 0.5]) else {
            return // Image I/O on this platform can't write an APNG
        }

        let source = try #require(AnimatedImageSource(data: data))

        // Image I/O reads them back as `Float`s, hence the tolerance.
        let expected = [0.1, 0.013, 0.02, 0.5]
        #expect(source.delays.count == expected.count)
        for (delay, value) in zip(source.delays, expected) {
            #expect(abs(delay - value) < 0.000_001)
        }
    }

    @Test func apngLoopCountIsRead() throws {
        guard let data = Test.animatedPNG(frameCount: 2, loopCount: 7) else {
            return // Image I/O on this platform can't write an APNG
        }

        #expect(try #require(AnimatedImageSource(data: data)).loopCount == 7)
    }

    // MARK: Container Dictionaries

    @Test func formatIsIdentifiedByItsContainerDictionary() {
        let empty: [CFString: Any] = [:]
        #expect(AnimatedImageFormat(properties: [kCGImagePropertyGIFDictionary: empty]) == .gif)
        #expect(AnimatedImageFormat(properties: [kCGImagePropertyPNGDictionary: empty]) == .png)
        #expect(AnimatedImageFormat(properties: [kCGImagePropertyWebPDictionary: empty]) == .webp)
        #expect(AnimatedImageFormat(properties: [kCGImagePropertyHEICSDictionary: empty]) == .heics)
        #expect(AnimatedImageFormat(properties: [kCGImagePropertyAVISDictionary: empty]) == .avis)
    }

    @Test func stillMetadataIdentifiesNoFormat() {
        // What a page stack or a still publishes: dictionaries, just none of
        // the ones an animation is described in.
        let empty: [CFString: Any] = [:]
        #expect(AnimatedImageFormat(properties: [:]) == nil)
        #expect(AnimatedImageFormat(properties: [
            kCGImagePropertyTIFFDictionary: empty,
            kCGImagePropertyExifDictionary: empty,
            kCGImagePropertyJFIFDictionary: empty,
            kCGImagePropertyFileSize: 1024
        ]) == nil)
    }

    @Test func loopCountFallsBackPerFormatWhenThereIsNoContainerDictionary() {
        #expect(AnimatedImageFormat.gif.loopCount(in: [:]) == 1)
        for format in [AnimatedImageFormat.png, .webp, .heics, .avis] {
            #expect(format.loopCount(in: [:]) == 0)
        }
    }

    @Test func loopCountThatIsNotANumberFallsBack() {
        let properties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: "3"] as [CFString: Any]
        ]
        #expect(AnimatedImageFormat.gif.loopCount(in: properties) == 1)
    }

    @Test func eachFormatReadsItsOwnDictionary() {
        // A loop count filed under another format's dictionary is not this
        // format's loop count.
        let properties: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 5] as [CFString: Any]
        ]
        #expect(AnimatedImageFormat.png.loopCount(in: properties) == 5)
        #expect(AnimatedImageFormat.gif.loopCount(in: properties) == 1)
        #expect(AnimatedImageFormat.webp.loopCount(in: properties) == 0)
    }

    // MARK: Not Animations

    @Test func iconWithSeveralSizesIsNotAnAnimation() throws {
        // An ICO holds several images of one icon, and Image I/O counts each
        // of them as a frame.
        guard let data = makeMultiSizeIcon(sizes: [16, 32]) else {
            return // No ICO encoder on this platform
        }
        let imageSource = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetCount(imageSource) == 2)

        #expect(AnimatedImageSource(data: data) == nil)
        let container = try ImageDecoders.Default().decode(data)
        #expect(container.type == .ico)
        #expect(container.animation == nil)
    }

    // MARK: Truncated Data

    @Test func truncatedAnimationDescribesTheFramesItHas() async throws {
        let data = Test.data(name: "cat", extension: "gif")
        let full = try #require(AnimatedImageSource(data: data))

        let source = try #require(AnimatedImageSource(data: data[...120000]))

        #expect(source.frameCount > 1)
        #expect(source.frameCount < full.frameCount)
        #expect(source.delays.count == source.frameCount)
        #expect(source.size == full.size)
        let frame = try #require(await source.makeFrameDecoder().decode(at: 0))
        #expect(CGSize(width: frame.width, height: frame.height) == source.size)
    }

    // MARK: Animations Described by the Caller

    @Test func frameDecoderIsMadeOnlyWhenAskedForAndGetsTheLimit() throws {
        // Documented: an animation sitting in the memory cache with nothing
        // playing it must not hold a decoder, so making the source mustn't
        // make one.
        let flipbook = try #require(Flipbook(data: Flipbook.encode()))
        let requests = FrameDecoderLimitLog()
        let made = AnimatedImageSource(
            data: Data(),
            delays: flipbook.delays,
            size: flipbook.size,
            makeFrameDecoder: { maxPixelSize in
                requests.append(maxPixelSize)
                return FlipbookFrameDecoder(flipbook, maxPixelSize: maxPixelSize)
            }
        )
        let source = try #require(made)
        #expect(requests.all.isEmpty)

        _ = source.makeFrameDecoder(maxPixelSize: 4)
        _ = source.makeFrameDecoder()

        #expect(requests.all == [4, nil])
    }

    @Test func negativeLoopCountMeansForever() throws {
        let flipbook = try #require(Flipbook(data: Flipbook.encode()))
        let made = AnimatedImageSource(
            data: Data(),
            delays: [0.1, 0.1],
            loopCount: -3,
            size: CGSize(width: 8, height: 8),
            makeFrameDecoder: { FlipbookFrameDecoder(flipbook, maxPixelSize: $0) }
        )

        #expect(try #require(made).loopCount == 0)
    }

    @Test func notANumberDelayIsAMissingOne() throws {
        let flipbook = try #require(Flipbook(data: Flipbook.encode()))
        let made = AnimatedImageSource(
            data: Data(),
            delays: [.nan, 0.2, -.infinity],
            size: CGSize(width: 8, height: 8),
            makeFrameDecoder: { FlipbookFrameDecoder(flipbook, maxPixelSize: $0) }
        )
        let source = try #require(made)

        #expect(source.delays == [0.1, 0.2, 0.1])
        #expect(abs(source.duration - 0.4) < 0.0001)
    }

    @Test func canvasWithNoAreaIsRefused() {
        let flipbook = Flipbook(data: Flipbook.encode())!
        for size in [CGSize(width: 8, height: 0), CGSize(width: 0, height: 8), CGSize(width: -8, height: 8), CGSize(width: CGFloat.nan, height: 8)] {
            let made = AnimatedImageSource(
                data: Data(),
                delays: [0.1, 0.1],
                size: size,
                makeFrameDecoder: { FlipbookFrameDecoder(flipbook, maxPixelSize: $0) }
            )
            #expect(made == nil)
        }
    }

    // MARK: Decoding the Frames of a Parsed Animation

    @Test func imageIOFrameDecoderHonorsTheLimitItIsMadeWith() async throws {
        let source = try #require(AnimatedImageSource(data: Test.data(name: "cat", extension: "gif")))

        let frame = try #require(await source.makeFrameDecoder(maxPixelSize: 100).decode(at: 1))

        #expect(frame.width == 100)
        #expect(frame.height == 56)
    }
}

// MARK: - Helpers

/// A GIF89a of 1×1 frames with nothing but the image data: no graphic
/// control extension and no application extension.
private func makeGIFWithoutExtensions(frameCount: Int, screenSize: UInt8 = 1) -> Data {
    var data = Data("GIF89a".utf8)
    // The logical screen, and a global color table of two colors.
    data += Data([screenSize, 0x00, screenSize, 0x00, 0x80, 0x00, 0x00])
    data += Data([0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF])
    for _ in 0..<frameCount {
        // An image descriptor, then the LZW data for a single pixel.
        data += Data([0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00])
        data += Data([0x02, 0x02, 0x44, 0x01, 0x00])
    }
    data += Data([0x3B])
    return data
}

private func makeMultiSizeIcon(sizes: [Int]) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.ico.identifier as CFString, sizes.count, nil) else {
        return nil
    }
    for size in sizes {
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    }
    guard CGImageDestinationFinalize(destination) else {
        return nil
    }
    return data as Data
}

/// The limits a frame decoder factory was called with.
private final class FrameDecoderLimitLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CGFloat?] = []

    var all: [CGFloat?] { lock.withLock { storage } }

    func append(_ value: CGFloat?) {
        lock.withLock { storage.append(value) }
    }
}
