// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite struct ImageEncodingProtocolTests {

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
}
