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

    @Test func gifContainerWithoutDataEncodesStill() throws {
        // GIVEN a GIF-typed container with no associated data (e.g. a processed GIF)
        let encoder = ImageEncoders.Default()
        let container = ImageContainer(image: Test.image, type: .gif, data: nil)
        let context = ImageEncodingContext(
            request: Test.request,
            image: Test.image,
            urlResponse: nil
        )

        // WHEN
        let result = try #require(encoder.encode(container, context: context))

        // THEN the still image is encoded
        #expect(!result.isEmpty)
        #expect(AssetType(result) != .gif)
    }

    @Test func gifThumbnailIsEncoded() throws {
        // GIVEN a thumbnail of a GIF, which the decoder gives no data
        var request = Test.request
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 4)
        let gif = Test.animatedGIF()
        let decoder = try #require(ImageDecoders.Default(context: ImageDecodingContext(request: request, data: gif, previewPolicy: .disabled)))
        let container = try decoder.decode(gif)
        #expect(container.type == .gif)
        #expect(container.data == nil)
        let context = ImageEncodingContext(
            request: request,
            image: container.image,
            urlResponse: nil
        )

        // WHEN
        let result = try #require(ImageEncoders.Default().encode(container, context: context))

        // THEN the thumbnail can be stored in the disk cache
        #expect(!result.isEmpty)
    }

    // MARK: - Animated Pass-Through

    private var context: ImageEncodingContext {
        ImageEncodingContext(request: Test.request, image: Test.image, urlResponse: nil)
    }

    @Test(arguments: AnimatedFixture.allCases)
    func encodeContainerPassesThroughAnimatedData(fixture: AnimatedFixture) throws {
        guard let data = fixture.data else {
            return // Image I/O on this platform can't write the fixture
        }
        let container = try ImageDecoders.Default().decode(data)
        #expect(container.animation != nil)

        #expect(ImageEncoders.Default().encode(container, context: context) == data)
        #expect(ImageEncoders.ImageIO(type: .jpeg).encode(container, context: context) == data)
    }

    /// With parsing off, the decoder attaches the data but no animation, and
    /// the same header check it attached the data on is the one that's left.
    @Test(arguments: AnimatedFixture.allCases)
    func encodeContainerPassesThroughAnimatedDataWithParsingDisabled(fixture: AnimatedFixture) throws {
        guard let data = fixture.data else { return }
        let decodingContext = ImageDecodingContext(request: Test.request, data: data, isAnimatedImageParsingEnabled: false)
        let container = try #require(ImageDecoders.Default(context: decodingContext)).decode(data)
        #expect(container.animation == nil)
        #expect(container.data == data)

        #expect(ImageEncoders.Default().encode(container, context: context) == data)
    }

    /// A decoder of your own can publish the bytes in the animation alone.
    @Test func encodeContainerPassesThroughTheDataOfACustomAnimation() throws {
        // Given an animation in a format `AssetType` doesn't know
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let animation = AnimatedImageSource(
            data: data,
            delays: [0.1, 0.1],
            size: CGSize(width: 8, height: 8),
            makeFrameDecoder: { _ in fatalError("Encoding decodes no frames") }
        )
        let container = ImageContainer(image: Test.image, animation: try #require(animation))

        // Then
        #expect(ImageEncoders.Default().encode(container, context: context) == data)
    }

    @Test(arguments: AnimatedFixture.allCases)
    func encodeContainerEncodesAnAnimatedImageWithoutItsData(fixture: AnimatedFixture) throws {
        guard let data = fixture.data else { return }
        // Given what `ImageProcessing` leaves of an animation: the type stays,
        // and the data and the animation don't
        let container = try ImageDecoders.Default().decode(data).map { $0 }
        #expect(container.type != nil)
        #expect(container.data == nil)
        #expect(container.animation == nil)

        // When
        let encoded = try #require(ImageEncoders.Default().encode(container, context: context))

        // Then
        #expect(encoded != data)
        #expect(AnimatedImageSource(data: encoded) == nil)
    }

    /// `ImageContainer/data` alone says nothing about the image: a decoder can
    /// attach it to any image, and the point of encoding is to replace it.
    @Test func encodeContainerDoesNotPassThroughTheDataOfAStill() {
        for (type, data) in [
            (AssetType.png, Test.staticPNG()),
            (AssetType.jpeg, Test.data),
            (AssetType.webp, Test.data(name: "baseline", extension: "webp")),
            (AssetType.heic, Test.data(name: "img_751", extension: "heic"))
        ] {
            // Given
            let encoder = RecordingEncoder()
            let container = ImageContainer(image: Test.image, type: type, data: data)

            // Then
            #expect(encoder.encode(container, context: context) == RecordingEncoder.output)
            #expect(encoder.encodedImages.count == 1)
        }
    }

    /// An encoder that implements the method is in charge of what it does.
    @Test func customEncoderCanEncodeAnimationsItself() throws {
        // Given
        struct FrameEncoder: ImageEncoding {
            static let output = Data([0x04, 0x05])
            func encode(_ image: PlatformImage) -> Data? { nil }
            func encode(_ container: ImageContainer, context: ImageEncodingContext) -> Data? { FrameEncoder.output }
        }
        let container = try ImageDecoders.Default().decode(Test.data(name: "animated", extension: "webp"))
        #expect(container.animation != nil)

        // Then
        #expect(FrameEncoder().encode(container, context: context) == FrameEncoder.output)
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

    /// So does the rest of what `ImageDecoders.Default` calls an animation.
    @Test(arguments: AnimatedFixture.allCases)
    func customEncoderPassesThroughAnimatedDataWithoutEncoding(fixture: AnimatedFixture) throws {
        guard let data = fixture.data else { return }

        // Given
        let encoder = RecordingEncoder()
        let container = try ImageDecoders.Default().decode(data)

        // Then
        #expect(encoder.encode(container, context: context) == data)
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
