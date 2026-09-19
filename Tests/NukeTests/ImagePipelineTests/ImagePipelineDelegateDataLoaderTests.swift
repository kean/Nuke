// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// ``ImagePipeline/Delegate-swift.protocol/dataLoader(for:pipeline:)``.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDelegateDataLoaderTests {
    private let dataLoader = MockDataLoader()
    private let delegate = DataLoaderDelegate()

    private func makePipeline(_ configure: (inout ImagePipeline.Configuration) -> Void = { _ in }) -> ImagePipeline {
        ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            configure(&$0)
        }
    }

    @Test func pipelineLoadsWithTheDataLoaderFromTheDelegate() async throws {
        // GIVEN a delegate that loads the avatars with their own loader
        let avatarLoader = MockDataLoader()
        delegate.dataLoader = { $0.userInfo["kind"] as? String == "avatar" ? avatarLoader : nil }
        let pipeline = makePipeline()
        let avatar = ImageRequest(url: Test.url).with { $0.userInfo["kind"] = "avatar" }

        // WHEN
        _ = try await pipeline.image(for: avatar)
        _ = try await pipeline.image(for: URL(string: "http://test.com/other.jpeg")!)

        // THEN each request is loaded by its own loader
        #expect(avatarLoader.createdTaskCount == 1)
        #expect(dataLoader.createdTaskCount == 1)
        #expect(delegate.requests.map(\.url) == [Test.url, URL(string: "http://test.com/other.jpeg")])
    }

    @Test func dataLoaderIsNotRequestedWhenThereIsNothingToDownload() async throws {
        // GIVEN
        let dataCache = MockDataCache()
        dataCache.store[Test.url.absoluteString] = Test.data
        let pipeline = makePipeline {
            $0.imageCache = MockImageCache()
            $0.dataCache = dataCache
        }
        pipeline.cache[ImageRequest(url: URL(string: "http://test.com/memory.jpeg"))] = Test.container

        // WHEN the images come from the memory cache, the disk cache, a local
        // file, and a closure
        _ = try await pipeline.image(for: URL(string: "http://test.com/memory.jpeg")!)
        _ = try await pipeline.image(for: Test.url)
        _ = try await pipeline.image(for: Test.url(forResource: "fixture", extension: "jpeg"))
        _ = try await pipeline.image(for: ImageRequest(id: "closure", data: { Test.data }))

        // THEN
        #expect(delegate.requests.isEmpty)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func dataLoaderIsRequestedOncePerDownload() async throws {
        // GIVEN
        let pipeline = makePipeline()

        // WHEN two requests wait for the same download
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: Test.request),
             pipeline.imageTask(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])))
        }
        _ = try await task1.response
        _ = try await task2.response

        // THEN
        #expect(delegate.requests.count == 1)
        #expect(dataLoader.createdTaskCount == 1)
    }
}

// MARK: - Helpers

private final class DataLoaderDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    /// Returns the loader for the request, or `nil` for the default one.
    var dataLoader: ((ImageRequest) -> (any DataLoading)?)?

    private let _requests = LockedArray<ImageRequest>()
    var requests: [ImageRequest] { _requests.values }

    func dataLoader(for request: ImageRequest, pipeline: ImagePipeline) -> any DataLoading {
        _requests.append(request)
        return dataLoader?(request) ?? pipeline.configuration.dataLoader
    }
}
