// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite struct ImagePipelineDecodingTests {
    let dataLoader: MockDataLoader
    let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    @Test func experimentalDecoder() async throws {
        // Given
        let decoder = MockExperimentalDecoder()

        let dummyImage = PlatformImage()
        let dummyData = "123".data(using: .utf8)
        decoder._decode = { data in
            return ImageContainer(image: dummyImage, data: dummyData, userInfo: ["a": 1])
        }

        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in decoder }
        }

        // When
        let response = try await pipeline.imageTask(with: Test.request).response

        // Then
        let container = response.container
        #expect(container.data == dummyData)
        #expect(container.userInfo["a"] as? Int == 1)
    }
}

private final class MockExperimentalDecoder: ImageDecoding, @unchecked Sendable {
    var _decode: ((Data) -> ImageContainer?)!

    func decode(_ data: Data) throws -> ImageContainer {
        guard let image = _decode(data) else {
            throw ImageDecodingError.unknown
        }
        return image
    }
}
