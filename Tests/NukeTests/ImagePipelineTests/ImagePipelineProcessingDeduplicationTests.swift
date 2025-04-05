// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

// TODO: reimplement
//@Suite struct ImagePipelineProcessingDeduplicationTests {
//    var dataLoader: MockDataLoader!
//    var pipeline: ImagePipeline!
//    var observations = [NSKeyValueObservation]()
//
//    init() {
//        super.setUp()
//
//        dataLoader = MockDataLoader()
//        pipeline = ImagePipeline {
//            $0.dataLoader = dataLoader
//            $0.imageCache = nil
//        }
//    }
//
//    @Test func eachProcessingStepIsDeduplicated() {
//        // Given requests with the same URLs but different processors
//        let processors = MockProcessorFactory()
//        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
//        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "1"), processors.make(id: "2")])
//
//        // When
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadImage(with: request1) { result in
//                let image = result.value?.image
//                #expect(image?.nk_test_processorIDs ?? [] == ["1"])
//            }
//            expect(pipeline).toLoadImage(with: request2) { result in
//                let image = result.value?.image
//                #expect(image?.nk_test_processorIDs ?? [] == ["1", "2"])
//            }
//        }
//
//        // Then the processor "1" is only applied once
//        wait { _ in
//            #expect(processors.numberOfProcessorsApplied == 2)
//        }
//    }
//
//    @Test func eachFinalProcessedImageIsStoredInMemoryCache() {
//        let cache = MockImageCache()
//        var conf = pipeline.configuration
//        conf.imageCache = cache
//        pipeline = ImagePipeline(configuration: conf)
//
//        // Given requests with the same URLs but different processors
//        let processors = MockProcessorFactory()
//        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
//        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "1"), processors.make(id: "2"), processors.make(id: "3")])
//
//        // When
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadImage(with: request1)
//            expect(pipeline).toLoadImage(with: request2)
//        }
//
//        // Then
//        wait { _ in
//            #expect(cache[request1] != nil)
//            #expect(cache[request2] != nil)
//            #expect(cache[ImageRequest(url: Test.url, processors: [processors.make(id: "1"), processors.make(id: "2")])] == nil)
//        }
//    }
//
//    @Test func whenApplingMultipleImageProcessorsIntermediateMemoryCachedResultsAreUsed() {
//        let cache = MockImageCache()
//        var conf = pipeline.configuration
//        conf.imageCache = cache
//        pipeline = ImagePipeline(configuration: conf)
//
//        let factory = MockProcessorFactory()
//
//        // Given
//        cache[ImageRequest(url: Test.url, processors: [factory.make(id: "1"), factory.make(id: "2")])] = Test.container
//
//        // When
//        let request = ImageRequest(url: Test.url, processors: [factory.make(id: "1"), factory.make(id: "2"), factory.make(id: "3")])
//        expect(pipeline).toLoadImage(with: request) { result in
//            guard let image = result.value?.image else {
//                return Issue.record("Expected image to be loaded successfully")
//            }
//            #expect(image.nk_test_processorIDs == ["3"], "Expected only the last processor to be applied")
//        }
//
//        // Then
//        wait { _ in
//            #expect(self.dataLoader.createdTaskCount == 0, "Expected no data task to be performed")
//            #expect(factory.numberOfProcessorsApplied == 1, "Expected only one processor to be applied")
//        }
//    }
//
//    @Test func whenApplingMultipleImageProcessorsIntermediateDataCacheResultsAreUsed() {
//        // Given
//        let dataCache = MockDataCache()
//        dataCache.store[Test.url.absoluteString + "12"] = Test.data
//
//        pipeline = pipeline.reconfigured {
//            $0.dataCache = dataCache
//        }
//
//        // When
//        let factory = MockProcessorFactory()
//        let request = ImageRequest(url: Test.url, processors: [factory.make(id: "1"), factory.make(id: "2"), factory.make(id: "3")])
//        expect(pipeline).toLoadImage(with: request) { result in
//            guard let image = result.value?.image else {
//                return Issue.record("Expected image to be loaded successfully")
//            }
//            #expect(image.nk_test_processorIDs == ["3"], "Expected only the last processor to be applied")
//        }
//
//        wait { _ in
//            #expect(self.dataLoader.createdTaskCount == 0, "Expected no data task to be performed")
//            #expect(factory.numberOfProcessorsApplied == 1, "Expected only one processor to be applied")
//        }
//    }
//
//    @Test func thatProcessingDeduplicationCanBeDisabled() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.isTaskCoalescingEnabled = false
//        }
//
//        // Given requests with the same URLs but different processors
//        let processors = MockProcessorFactory()
//        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
//        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "1"), processors.make(id: "2")])
//
//        // When
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadImage(with: request1) { result in
//                let image = result.value?.image
//                #expect(image?.nk_test_processorIDs ?? [] == ["1"])
//            }
//            expect(pipeline).toLoadImage(with: request2) { result in
//                let image = result.value?.image
//                #expect(image?.nk_test_processorIDs ?? [] == ["1", "2"])
//            }
//        }
//
//        // Then the processor "1" is applied twice
//        wait { _ in
//            #expect(processors.numberOfProcessorsApplied == 3)
//        }
//    }
//
//    @Test func thatDataOnlyLoadedOnceWithDifferentCachePolicy() {
//        // Given
//        let dataCache = MockDataCache()
//        pipeline = pipeline.reconfigured {
//            $0.dataCache = dataCache
//        }
//
//        // When
//        func makeRequest(options: ImageRequest.Options) -> ImageRequest {
//            ImageRequest(urlRequest: URLRequest(url: Test.url), options: options)
//        }
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadImage(with: makeRequest(options: []))
//            expect(pipeline).toLoadImage(with: makeRequest(options: [.reloadIgnoringCachedData]))
//        }
//
//        // Then
//        wait { _ in
//            #expect(self.dataLoader.createdTaskCount == 1, "Expected only one data task to be performed")
//        }
//    }
//
//    @Test func thatDataOnlyLoadedOnceWithDifferentCachePolicyPassingURL() {
//        // Given
//        let dataCache = MockDataCache()
//        pipeline = pipeline.reconfigured {
//            $0.dataCache = dataCache
//        }
//
//        // When
//        // - One request reloading cache data, another one not
//        func makeRequest(options: ImageRequest.Options) -> ImageRequest {
//            ImageRequest(urlRequest: URLRequest(url: Test.url), options: options)
//        }
//
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadImage(with: makeRequest(options: []))
//            expect(pipeline).toLoadImage(with: makeRequest(options: [.reloadIgnoringCachedData]))
//        }
//
//        // Then
//        wait { _ in
//            #expect(self.dataLoader.createdTaskCount == 1, "Expected only one data task to be performed")
//        }
//    }
//}
