// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDecodingTests {
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

    @Test func asyncDecoder() async throws {
        // Given
        let expectedData = Data("async-decoder".utf8)
        let decoder = MockAsyncDecoder { _ in
            await Task.yield()
            return ImageContainer(image: PlatformImage(), data: expectedData)
        }

        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in decoder }
        }

        // When
        let response = try await pipeline.imageTask(with: Test.request).response

        // Then
        #expect(response.container.data == expectedData)
    }

    // MARK: - Decoder Errors

    @Test func decoderReturningNilResultsInDecodingFailedError() async throws {
        // GIVEN a decoder whose _decode closure returns nil (causes decode() to throw)
        let decoder = MockExperimentalDecoder()
        decoder._decode = { _ in nil }

        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in decoder }
        }

        // WHEN
        do {
            _ = try await pipeline.imageTask(with: Test.request).response
            Issue.record("Expected a decoding error")
        } catch {
            // THEN the pipeline wraps it in a decodingFailed error
            if case .decodingFailed = error {
                // Expected
            } else {
                Issue.record("Expected decodingFailed, got \(error)")
            }
        }
    }

    @Test func whenDecoderFactoryReturnsNilPipelineErrors() async throws {
        // GIVEN a pipeline where no decoder can handle the content
        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in nil }
        }

        // WHEN
        do {
            _ = try await pipeline.imageTask(with: Test.request).response
            Issue.record("Expected decoderNotRegistered error")
        } catch {
            // THEN
            if case .decoderNotRegistered = error {
                // Expected
            } else {
                Issue.record("Expected decoderNotRegistered, got \(error)")
            }
        }
    }

    @Test func asyncDecoderErrorIsWrapped() async throws {
        // Given
        let expectedError = MockError(description: "async-decoder-failed")
        let decoder = MockAsyncDecoder { _ in
            await Task.yield()
            throw expectedError
        }

        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in decoder }
        }

        // When
        do {
            _ = try await pipeline.imageTask(with: Test.request).response
            Issue.record("Expected a decoding error")
        } catch {
            // Then
            guard case let .decodingFailed(failedDecoder, context, underlyingError) = error else {
                Issue.record("Expected decodingFailed, got \(error)")
                return
            }
            #expect((failedDecoder as? MockAsyncDecoder) === decoder)
            #expect(context.data == Test.data)
            #expect(underlyingError as? MockError == expectedError)
        }
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

private final class MockAsyncDecoder: AsyncImageDecoding, @unchecked Sendable {
    private let _decode: @Sendable (Data) async throws -> ImageContainer

    init(_ decode: @escaping @Sendable (Data) async throws -> ImageContainer) {
        self._decode = decode
    }

    func decode(_ data: Data) async throws -> ImageContainer {
        try await _decode(data)
    }
}
