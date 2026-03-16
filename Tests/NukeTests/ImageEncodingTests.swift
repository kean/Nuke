// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(2)))
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
}
