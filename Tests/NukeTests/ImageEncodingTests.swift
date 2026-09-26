// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImageEncodingProtocolTests {

    // MARK: - Default encode(container:context:) for GIF pass-through

    @Test func encodeContainerPassesThroughGIFData() {
        let encoder = ImageEncoders.Default()
        let gifData = Test.data(name: "cat", extension: "gif")
        let container = ImageContainer(image: Test.image, type: .gif, data: gifData)
        let context = ImageEncodingContext(
            request: Test.request,
            image: Test.image,
            urlResponse: nil
        )

        let result = encoder.encode(container, context: context)
        #expect(result == gifData)
    }

    @Test func encodeContainerEncodesNonGIFNormally() throws {
        let encoder = ImageEncoders.Default()
        let container = ImageContainer(image: Test.image, type: .jpeg)
        let context = ImageEncodingContext(
            request: Test.request,
            image: Test.image,
            urlResponse: nil
        )

        let result = try #require(encoder.encode(container, context: context))
        #expect(!result.isEmpty)
    }

    // MARK: - Factory methods

    @Test func defaultFactoryMethod() throws {
        let encoder: ImageEncoders.Default = .default()
        let data = try #require(encoder.encode(Test.image))
        #expect(!data.isEmpty)
    }

    @Test func defaultFactoryMethodWithCompression() throws {
        let encoder: ImageEncoders.Default = .default(compressionQuality: 0.5)
        let data = try #require(encoder.encode(Test.image))
        #expect(!data.isEmpty)
    }

    @Test func imageIOFactoryMethod() throws {
        let encoder: ImageEncoders.ImageIO = .imageIO(type: .png)
        let data = try #require(encoder.encode(Test.image))
        #expect(AssetType(data) == .png)
    }

    @Test func imageIOFactoryMethodWithCompression() throws {
        let encoder: ImageEncoders.ImageIO = .imageIO(type: .jpeg, compressionRatio: 0.5)
        let data = try #require(encoder.encode(Test.image))
        #expect(!data.isEmpty)
    }

    // MARK: - GIF Pass-Through Edge Cases

    @Test func gifContainerWithoutDataReturnsNil() throws {
        // GIVEN a GIF-typed container with no associated data (animation data lost)
        let encoder = ImageEncoders.Default()
        let container = ImageContainer(image: Test.image, type: .gif, data: nil)
        let context = ImageEncodingContext(
            request: Test.request,
            image: Test.image,
            urlResponse: nil
        )

        // WHEN
        let result = encoder.encode(container, context: context)

        // THEN returns nil — GIF encoding requires the original animated data
        #expect(result == nil)
    }

    // MARK: - Context

    @Test func encodingContextContainsExpectedValues() {
        let context = ImageEncodingContext(
            request: Test.request,
            image: Test.image,
            urlResponse: nil
        )

        #expect(context.request.url == Test.url)
        #expect(context.urlResponse == nil)
    }

    // MARK: - ImageEncoders.ImageIO

    @Test func imageIOEncoderProducesJPEGData() throws {
        let encoder = ImageEncoders.ImageIO(type: .jpeg)
        let data = try #require(encoder.encode(Test.image))
        #expect(AssetType(data) == .jpeg)
    }

    @Test func imageIOEncoderProducesPNGData() throws {
        let encoder = ImageEncoders.ImageIO(type: .png)
        let data = try #require(encoder.encode(Test.image))
        #expect(AssetType(data) == .png)
    }

    @Test func imageIOEncoderIsSupportedForJPEG() {
        #expect(ImageEncoders.ImageIO.isSupported(type: .jpeg))
    }

    @Test func imageIOEncoderIsSupportedForPNG() {
        #expect(ImageEncoders.ImageIO.isSupported(type: .png))
    }

    @Test func imageIOEncoderIsNotSupportedForUnknownType() {
        #expect(!ImageEncoders.ImageIO.isSupported(type: AssetType(rawValue: "com.github.kean.nuke.not-a-real-type")))
    }

    @Test func imageIOEncoderReturnsNilForImageWithoutCGImage() {
        // Given an image with no backing `CGImage`
        let encoder = ImageEncoders.ImageIO(type: .png)

        // Then
        #expect(encoder.encode(PlatformImage()) == nil)
    }

    @Test func imageIOHigherCompressionProducesLargerData() throws {
        let lowQuality = ImageEncoders.ImageIO(type: .jpeg, compressionRatio: 0.1)
        let highQuality = ImageEncoders.ImageIO(type: .jpeg, compressionRatio: 0.9)
        let lowData = try #require(lowQuality.encode(Test.image))
        let highData = try #require(highQuality.encode(Test.image))
        #expect(highData.count > lowData.count)
    }

    @Test func imageIOEncoderDefaultCompressionRatio() {
        let encoder = ImageEncoders.ImageIO(type: .jpeg)
        #expect(encoder.compressionRatio == 0.8)
    }

    // MARK: - Support Matrix

    /// The formats "Supported Formats" lists as encodable on every platform.
    @Test(arguments: [AssetType.jpeg, .png, .gif, .heic, .jpeg2000, .tiff, .bmp, .ico])
    func imageIOEncoderWritesTheRequestedFormat(type: AssetType) throws {
        // Given
        #expect(ImageEncoders.ImageIO.isSupported(type: type))

        // When
        let data = try #require(ImageEncoders.ImageIO(type: type).encode(Test.rgbImage(width: 64, height: 64)))

        // Then the output is in the requested format and decodes back
        #expect(AssetType(data) == type)
        let decoded = try ImageDecoders.Default().decode(data)
        #expect(decoded.image.sizeInPixels == CGSize(width: 64, height: 64))
    }

    /// AVIF is the one format "Supported Formats" lists as encodable only on
    /// recent OS versions, which `isSupported(type:)` is documented to answer.
    @Test func imageIOEncoderWritesAVIFWhenSupported() throws {
        let type = AssetType.avif
        guard ImageEncoders.ImageIO.isSupported(type: type) else {
            #expect(ImageEncoders.ImageIO(type: type).encode(Test.rgbImage(width: 64, height: 64)) == nil)
            return
        }
        let data = try #require(ImageEncoders.ImageIO(type: type).encode(Test.rgbImage(width: 64, height: 64)))
        #expect(AssetType(data) == type)
    }

    /// Image I/O has no WebP or JPEG XL encoder on any current platform.
    @Test(arguments: [AssetType.webp, .jxl])
    func imageIOEncoderReportsTheFormatsWithoutAnEncoder(type: AssetType) {
        #expect(!ImageEncoders.ImageIO.isSupported(type: type))
        #expect(ImageEncoders.ImageIO(type: type).encode(Test.image) == nil)
    }

    @Test func imageIOEncoderReturnsNilForUnknownType() {
        // Given a type Image I/O can't create a destination for
        let encoder = ImageEncoders.ImageIO(type: AssetType(rawValue: "com.github.kean.nuke.not-a-real-type"))

        // Then
        #expect(encoder.encode(Test.image) == nil)
    }

    /// An ICO can't hold an image larger than 256x256. The destination is
    /// created and the image added, but the encoding fails when it's finalized –
    /// the encoder must report that instead of returning an empty or partial file.
    @Test func imageIOEncoderReturnsNilWhenTheFormatRejectsTheImage() throws {
        // Given
        let encoder = ImageEncoders.ImageIO(type: .ico)
        #expect(ImageEncoders.ImageIO.isSupported(type: .ico))

        // Then the largest icon is encoded...
        let data = try #require(encoder.encode(Test.rgbImage(width: 256, height: 256)))
        #expect(AssetType(data) == .ico)

        // ...but not anything larger
        #expect(encoder.encode(Test.rgbImage(width: 257, height: 257)) == nil)
        #expect(encoder.encode(Test.image) == nil)
    }

    /// The quality is a fraction, but a value outside of `0...1` is not
    /// something to crash or fail on.
    @Test(arguments: [Float(-1), 0, 1, 2, .nan])
    func imageIOEncoderToleratesOutOfRangeCompressionRatio(compressionRatio: Float) throws {
        // When
        let data = try #require(ImageEncoders.ImageIO(type: .jpeg, compressionRatio: compressionRatio).encode(Test.image))

        // Then
        let decoded = try ImageDecoders.Default().decode(data)
        #expect(decoded.image.sizeInPixels == CGSize(width: 640, height: 480))
    }

    @Test func lowerCompressionRatioProducesSmallerHEIF() throws {
        // Given
        let low = ImageEncoders.ImageIO(type: .heic, compressionRatio: 0.1)
        let high = ImageEncoders.ImageIO(type: .heic, compressionRatio: 1)

        // Then
        let lowData = try #require(low.encode(Test.image))
        let highData = try #require(high.encode(Test.image))
        #expect(lowData.count < highData.count)
    }

    // MARK: - Protocol Default

    /// A custom encoder that implements only the basic method gets the GIF
    /// pass-through for free.
    @Test func customEncoderPassesThroughGIFDataWithoutEncoding() {
        // Given
        let encoder = RecordingEncoder()
        let gifData = Test.data(name: "cat", extension: "gif")
        let container = ImageContainer(image: Test.image, type: .gif, data: gifData)
        let context = ImageEncodingContext(request: Test.request, image: container.image, urlResponse: nil)

        // When
        let data = encoder.encode(container, context: context)

        // Then
        #expect(data == gifData)
        #expect(encoder.encodedImages.isEmpty)
    }

    @Test func customEncoderEncodesTheImageOfOtherContainers() {
        // Given
        let encoder = RecordingEncoder()
        let image = Test.image
        let container = ImageContainer(image: image, type: .jpeg, data: Test.data)
        let context = ImageEncodingContext(request: Test.request, image: image, urlResponse: nil)

        // When
        let data = encoder.encode(container, context: context)

        // Then the basic method is called with the image, and the data
        // attached to the container isn't used
        #expect(data == RecordingEncoder.output)
        #expect(encoder.encodedImages.count == 1)
        #expect(encoder.encodedImages.first === image)
    }
}

/// Records the images passed to the basic `encode(_:)` method.
private final class RecordingEncoder: ImageEncoding, @unchecked Sendable {
    static let output = Data([0x01, 0x02, 0x03])

    private let lock = NSLock()
    private var _encodedImages: [PlatformImage] = []

    var encodedImages: [PlatformImage] {
        lock.withLock { _encodedImages }
    }

    func encode(_ image: PlatformImage) -> Data? {
        lock.withLock { _encodedImages.append(image) }
        return RecordingEncoder.output
    }
}
