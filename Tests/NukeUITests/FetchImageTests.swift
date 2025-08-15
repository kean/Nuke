// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing

@testable import Nuke
@testable import NukeUI

@MainActor
@Suite struct FetchImageTests {
    var dataLoader: MockDataLoader!
    var imageCache: MockImageCache!
    var dataCache: MockDataCache!
    var observer: ImagePipelineObserver!
    var pipeline: ImagePipeline!
    var image: FetchImage!

    init() {
        dataLoader = MockDataLoader()
        imageCache = MockImageCache()
        observer = ImagePipelineObserver()
        dataCache = MockDataCache()

        pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
        }

        image = FetchImage()
        image.pipeline = pipeline
    }

    @Test func imageLoaded() async throws {
        // Given
        let expectation = image.$result.dropFirst()
            .expectToPublishValue()

        // When
        image.load(Test.request)
        let result = try #require(await expectation.value)

        // Then
        #expect(result.isSuccess)
        #expect(result.value != nil)
    }

    @Test func isLoadingUpdated() async {
        // Given
        let expectation1 = image.$result.dropFirst()
            .expectToPublishValue()
        let expectation2 = image.$isLoading.record(count: 3)

        // When
        image.load(Test.request)
        await expectation1.wait()

        // Then
        let isLoadingValues = await expectation2.wait()
        #expect(isLoadingValues == [false, true, false])
    }

    @Test func memoryCacheLookup() throws {
        // Given
        pipeline.cache[Test.request] = Test.container

        // When
        image.load(Test.request)

        // Then image loaded synchronously
        let result = try #require(image.result)
        #expect(result.isSuccess)
        let response = try #require(result.value)
        #expect(response.cacheType == .memory)
        #expect(image.image != nil)
    }

    @ImagePipelineActor
    @Test func priorityUpdated() async {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        // When
        let expectation = queue.expectJobAdded()
        Task { @MainActor in
            image.priority = .high
            image.load(Test.request)
        }

        // Then
        let job = await expectation.value
        #expect(job.priority == .high)
    }

    @ImagePipelineActor
    @Test func priorityUpdatedDynamically() async {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        // When
        let expectation1 = queue.expectJobAdded()
        Task { @MainActor in
            image.load(Test.request)
        }

        // Then
        let job = await expectation1.wait()

        // When
        let expectation2 = queue.expectPriorityUpdated(for: job)
        Task { @MainActor in
            image.priority = .high
        }

        // Then
        let priority = await expectation2.wait()
        #expect(priority == .high)
    }
}
