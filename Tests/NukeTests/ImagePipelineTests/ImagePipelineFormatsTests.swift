// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

@Suite struct ImagePipelineFormatsTests {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    init() {
        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    @Test func extendedColorSpaceSupport() async throws {
        // Given
        dataLoader.results[Test.url] = .success(
            (Test.data(name: "image-p3", extension: "jpg"), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let image = try await pipeline.image(for: Test.request)

        // Then
        let cgImage = try #require(image.cgImage)
        let colorSpace = try #require(cgImage.colorSpace)
#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
        #expect(colorSpace.isWideGamutRGB)
#elseif os(watchOS)
        #expect(!colorSpace.isWideGamutRGB)
#endif
    }

    @Test func grayscaleSupport() async throws {
        // Given
        dataLoader.results[Test.url] = .success(
            (Test.data(name: "grayscale", extension: "jpeg"), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let image = try await pipeline.image(for: Test.request)

        // Then
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.bitsPerComponent == 8)
    }
}
