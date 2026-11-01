// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import CoreGraphics
import os
@testable import Nuke

/// `isDecompressionEnabled` end to end, through a pipeline: the only
/// platform-specific part is its default.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDecompressionTests {
    let dataLoader = MockDataLoader()

    @Test func theDefaultFollowsThePlatform() {
        let configuration = ImagePipeline.Configuration()
#if os(macOS)
        #expect(!configuration.isDecompressionEnabled)
#else
        #expect(configuration.isDecompressionEnabled)
#endif
    }

    @Test func enablingDecompressionDecompressesTheImage() async throws {
        let delegate = DecompressionCountingDelegate()

        // When
        let response = try await makePipeline(isDecompressionEnabled: true, delegate: delegate)
            .imageTask(with: Test.request).response

        // Then the pipeline redrew it into a bitmap of its own
        #expect(delegate.decompressCount == 1)
        #expect(delegate.redrawnCount == 1)
        let output = try #require(response.image.cgImage)
        #expect(output.width == 640 && output.height == 480)
    }

    @Test func disablingDecompressionLeavesTheImageAsDecoded() async throws {
        let delegate = DecompressionCountingDelegate()

        let response = try await makePipeline(isDecompressionEnabled: false, delegate: delegate)
            .imageTask(with: Test.request).response

        #expect(delegate.decompressCount == 0)
        #expect(response.image.cgImage != nil)
    }

    @Test func skipDecompressionOverridesTheConfiguration() async throws {
        let delegate = DecompressionCountingDelegate()
        var request = Test.request
        request.options.insert(.skipDecompression)

        _ = try await makePipeline(isDecompressionEnabled: true, delegate: delegate)
            .imageTask(with: request).response

        #expect(delegate.decompressCount == 0)
    }

    private func makePipeline(isDecompressionEnabled: Bool, delegate: DecompressionCountingDelegate) -> ImagePipeline {
        ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isDecompressionEnabled = isDecompressionEnabled
        }
    }
}

/// Runs the default decompression and counts how many times it ran.
private final class DecompressionCountingDelegate: ImagePipeline.Delegate, Sendable {
    var decompressCount: Int { _decompressCount.withLock { $0 } }
    /// How many times the output was a different `CGImage` than the input.
    var redrawnCount: Int { _redrawnCount.withLock { $0 } }
    private let _decompressCount = OSAllocatedUnfairLock(initialState: 0)
    private let _redrawnCount = OSAllocatedUnfairLock(initialState: 0)

    func decompress(response: ImageResponse, request: ImageRequest, pipeline: ImagePipeline) -> ImageResponse {
        _decompressCount.withLock { $0 += 1 }
        var response = response
        let input = response.image.cgImage
        response.container.image = ImageDecompression.decompress(image: response.image, isUsingPrepareForDisplay: false)
        if let output = response.image.cgImage, output !== input {
            _redrawnCount.withLock { $0 += 1 }
        }
        return response
    }
}
