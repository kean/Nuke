// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// ``ImagePipeline/Delegate-swift.protocol/shouldDecompress(response:for:pipeline:)``
/// and ``ImagePipeline/Delegate-swift.protocol/decompress(response:request:pipeline:)``.
///
/// The decoder used here marks every image it produces as needing
/// decompression, which the default decoder does on every platform but macOS,
/// so the same tests run everywhere.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDelegateDecompressionTests {
    private let dataLoader = MockDataLoader()
    private let imageCache = MockImageCache()
    private let decoder = MarkingDecoder()

    private func makePipeline(delegate: any ImagePipeline.Delegate, isDecompressionEnabled: Bool = true) -> ImagePipeline {
        let decoder = self.decoder
        return ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.makeImageDecoder = { _ in decoder }
            $0.isDecompressionEnabled = isDecompressionEnabled
        }
    }

    // MARK: Default Implementation

    @Test func defaultHooksDecompressTheImageWhenEnabled() async throws {
        // GIVEN a delegate that relies on the default implementations
        let pipeline = makePipeline(delegate: PassthroughDelegate(), isDecompressionEnabled: true)

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN the response carries a decompressed copy of the decoded image
        let decoded = try #require(decoder.lastImage)
        #expect(response.image !== decoded)
        #expect(ImageDecompression.isDecompressionNeeded(for: response.image) == nil)
        #expect(response.image.sizeInPixels == decoded.sizeInPixels)

        // THEN the memory cache stores the decompressed image
        #expect(imageCache[ImageCacheKey(request: Test.request)]?.image === response.image)
    }

    @Test func defaultShouldDecompressFollowsTheConfiguration() async throws {
        // GIVEN
        let pipeline = makePipeline(delegate: PassthroughDelegate(), isDecompressionEnabled: false)

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN the decoded image is delivered as is
        #expect(response.image === decoder.lastImage)
        #expect(ImageDecompression.isDecompressionNeeded(for: response.image) == true)
    }

    // MARK: Custom Implementation

    @Test func shouldDecompressReturningFalseSkipsDecompression() async throws {
        // GIVEN
        let delegate = DecompressionDelegate()
        delegate.shouldDecompress = false
        let pipeline = makePipeline(delegate: delegate)

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN
        #expect(delegate.shouldDecompressRequests.map(\.url) == [Test.url])
        #expect(delegate.decompressCount == 0)
        #expect(response.image === decoder.lastImage)
    }

    /// The delegate wins over the configuration in both directions.
    @Test func shouldDecompressOverridesTheConfiguration() async throws {
        // GIVEN decompression disabled in the configuration
        let delegate = DecompressionDelegate()
        let pipeline = makePipeline(delegate: delegate, isDecompressionEnabled: false)

        // WHEN
        _ = try await pipeline.imageTask(with: Test.request).response

        // THEN
        #expect(delegate.decompressCount == 1)
    }

    @Test func delegateIsNotAskedWhenTheRequestSkipsDecompression() async throws {
        // GIVEN
        let delegate = DecompressionDelegate()
        let pipeline = makePipeline(delegate: delegate)

        // WHEN
        let request = ImageRequest(url: Test.url, options: [.skipDecompression])
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(delegate.shouldDecompressRequests.isEmpty)
        #expect(delegate.decompressCount == 0)
        #expect(response.image === decoder.lastImage)
    }

    @Test func memoryCacheHitsAreNotDecompressedAgain() async throws {
        // GIVEN an image in the memory cache that is marked as compressed
        let delegate = DecompressionDelegate()
        let pipeline = makePipeline(delegate: delegate)
        let cached = Test.image
        ImageDecompression.setDecompressionNeeded(true, for: cached)
        pipeline.cache[Test.request] = ImageContainer(image: cached)

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN
        #expect(response.image === cached)
        #expect(delegate.shouldDecompressRequests.isEmpty)
    }
}

// MARK: - Helpers

/// Decodes the image with the default decoder and marks it as needing
/// decompression, which is what the default decoder does on iOS and tvOS.
private final class MarkingDecoder: ImageDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private var _lastImage: PlatformImage?
    var lastImage: PlatformImage? { lock.withLock { _lastImage } }

    func decode(_ data: Data) throws -> ImageContainer {
        let container = try ImageDecoders.Default().decode(data)
        ImageDecompression.setDecompressionNeeded(true, for: container.image)
        lock.withLock { _lastImage = container.image }
        return container
    }
}

/// Relies on the default implementation of every method.
private final class PassthroughDelegate: ImagePipeline.Delegate, @unchecked Sendable {}

private final class DecompressionDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    var shouldDecompress = true

    private let lock = NSLock()
    private var _shouldDecompressRequests: [ImageRequest] = []
    private var _decompressCount = 0

    var shouldDecompressRequests: [ImageRequest] { lock.withLock { _shouldDecompressRequests } }
    var decompressCount: Int { lock.withLock { _decompressCount } }

    func shouldDecompress(response: ImageResponse, for request: ImageRequest, pipeline: ImagePipeline) -> Bool {
        lock.withLock { _shouldDecompressRequests.append(request) }
        return shouldDecompress
    }

    func decompress(response: ImageResponse, request: ImageRequest, pipeline: ImagePipeline) -> ImageResponse {
        lock.withLock { _decompressCount += 1 }
        return response
    }
}
