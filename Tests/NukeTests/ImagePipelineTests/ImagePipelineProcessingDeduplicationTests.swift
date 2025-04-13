// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

@ImagePipelineActor
@Suite class ImagePipelineProcessingDeduplicationTests {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!
    var observations = [NSKeyValueObservation]()

    init() {
        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    @Test func eachProcessingStepIsDeduplicated() async throws {
        // Given requests with the same URLs but different processors
        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "1"), processors.make(id: "2")])

        // When
        async let task1 = pipeline.image(for: request1)
        async let task2 = pipeline.image(for: request2)
        let (image1, image2) = try await (task1, task2)

        // Then
        #expect(image1.nk_test_processorIDs == ["1"])
        #expect(image2.nk_test_processorIDs == ["1", "2"])

        // Then the processor "1" is only applied once
        #expect(processors.numberOfProcessorsApplied == 2)
    }

    @Test func eachFinalProcessedImageIsStoredInMemoryCache() async throws {
        let cache = MockImageCache()
        var conf = pipeline.configuration
        conf.imageCache = cache
        pipeline = ImagePipeline(configuration: conf)

        // Given requests with the same URLs but different processors
        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "1"), processors.make(id: "2"), processors.make(id: "3")])

        // When
        async let task1 = pipeline.image(for: request1)
        async let task2 = pipeline.image(for: request2)
        _ = try await (task1, task2)

        // Then
        #expect(cache[request1] != nil)
        #expect(cache[request2] != nil)
        #expect(cache[ImageRequest(url: Test.url, processors: [processors.make(id: "1"), processors.make(id: "2")])] == nil)
    }

    @Test func whenApplingMultipleImageProcessorsIntermediateMemoryCachedResultsAreUsed() async throws {
        let cache = MockImageCache()
        var conf = pipeline.configuration
        conf.imageCache = cache
        pipeline = ImagePipeline(configuration: conf)

        let factory = MockProcessorFactory()

        // Given
        cache[ImageRequest(url: Test.url, processors: [factory.make(id: "1"), factory.make(id: "2")])] = Test.container

        // When
        let request = ImageRequest(url: Test.url, processors: [factory.make(id: "1"), factory.make(id: "2"), factory.make(id: "3")])
        let image = try await pipeline.image(for: request)

        // Then
        #expect(image.nk_test_processorIDs == ["3"], "Expected only the last processor to be applied")
        #expect(dataLoader.createdTaskCount == 0, "Expected no data task to be performed")
        #expect(factory.numberOfProcessorsApplied == 1, "Expected only one processor to be applied")
    }

    @Test func whenApplingMultipleImageProcessorsIntermediateDataCacheResultsAreUsed() async throws {
        // Given
        let dataCache = MockDataCache()
        dataCache.store[Test.url.absoluteString + "12"] = Test.data

        pipeline = pipeline.reconfigured {
            $0.dataCache = dataCache
        }

        // When
        let factory = MockProcessorFactory()
        let request = ImageRequest(url: Test.url, processors: [factory.make(id: "1"), factory.make(id: "2"), factory.make(id: "3")])
        let image = try await pipeline.image(for: request)

        // Then
        #expect(image.nk_test_processorIDs == ["3"], "Expected only the last processor to be applied")
        #expect(dataLoader.createdTaskCount == 0, "Expected no data task to be performed")
        #expect(factory.numberOfProcessorsApplied == 1, "Expected only one processor to be applied")
    }

    @Test func thatProcessingDeduplicationCanBeDisabled() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.isTaskCoalescingEnabled = false
        }

        // Given requests with the same URLs but different processors
        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "1"), processors.make(id: "2")])

        // When
        async let task1 = pipeline.image(for: request1)
        async let task2 = pipeline.image(for: request2)
        let (image1, image2) = try await (task1, task2)

        // Then
        #expect(image1.nk_test_processorIDs == ["1"])
        #expect(image2.nk_test_processorIDs == ["1", "2"])

        // Then the processor "1" is applied twice
        #expect(processors.numberOfProcessorsApplied == 3)
    }

    @Test func thatDataOnlyLoadedOnceWithDifferentCachePolicy() async throws {
        // Given
        let dataCache = MockDataCache()
        pipeline = pipeline.reconfigured {
            $0.dataCache = dataCache
        }

        // When
        func makeRequest(options: ImageRequest.Options) -> ImageRequest {
            ImageRequest(urlRequest: URLRequest(url: Test.url), options: options)
        }
        async let task1 = pipeline.image(for: makeRequest(options: []))
        async let task2 = pipeline.image(for: makeRequest(options: [.reloadIgnoringCachedData]))
        _ = try await (task1, task2)

        // Then
        #expect(dataLoader.createdTaskCount == 1, "Expected only one data task to be performed")
    }

    @Test func thatDataOnlyLoadedOnceWithDifferentCachePolicyPassingURL() async throws {
        // Given
        let dataCache = MockDataCache()
        pipeline = pipeline.reconfigured {
            $0.dataCache = dataCache
        }

        // When
        // - One request reloading cache data, another one not
        func makeRequest(options: ImageRequest.Options) -> ImageRequest {
            ImageRequest(url: Test.url, options: options)
        }
        async let task1 = pipeline.image(for: makeRequest(options: []))
        async let task2 = pipeline.image(for: makeRequest(options: [.reloadIgnoringCachedData]))
        _ = try await (task1, task2)


        // Then
        #expect(dataLoader.createdTaskCount == 1, "Expected only one data task to be performed")
    }
}
