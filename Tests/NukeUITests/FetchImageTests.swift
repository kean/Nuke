// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Combine
@testable import Nuke
@testable import NukeUI

@Suite @MainActor struct FetchImageTests {
    let dataLoader: MockDataLoader
    let observer: ImagePipelineObserver
    let pipeline: ImagePipeline
    var image: FetchImage

    init() {
        let dataLoader = MockDataLoader()
        let observer = ImagePipelineObserver()
        self.dataLoader = dataLoader
        self.observer = observer
        self.pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = MockImageCache()
            $0.dataCache = MockDataCache()
        }
        self.image = FetchImage()
        self.image.pipeline = pipeline
    }

    @Test func imageLoaded() async throws {
        let expectation = TestExpectation()
        image.onCompletion = { _ in expectation.fulfill() }
        image.load(Test.request)
        await expectation.wait()

        let result = try #require(image.result)
        #expect(result.isSuccess)
        #expect(image.image != nil)
    }

    @Test func isLoadingUpdated() async {
        #expect(!image.isLoading)

        let expectation = TestExpectation()
        image.onCompletion = { _ in expectation.fulfill() }
        image.load(Test.request)
        #expect(image.isLoading)

        await expectation.wait()
        #expect(!image.isLoading)
    }

    @Test func memoryCacheLookup() throws {
        pipeline.cache[Test.request] = Test.container

        image.load(Test.request)

        let result = try #require(image.result)
        #expect(result.isSuccess)
        let response = try #require(result.value)
        #expect(response.cacheType == .memory)
        #expect(image.image != nil)
    }

    @Test func priorityUpdated() async throws {
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        let observer = OperationQueueObserver(queue: queue)

        image.priority = .high
        image.load(Test.request)
        await waitForOperations(on: observer, count: 1)

        let operation = try #require(observer.operations.first)
        #expect(operation.queuePriority == .high)
    }

    @Test func priorityUpdatedDynamically() async throws {
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        let observer = OperationQueueObserver(queue: queue)

        image.load(Test.request)
        await waitForOperations(on: observer, count: 1)

        let operation = try #require(observer.operations.first)

        let expectation = TestExpectation()
        let kvoObserver = operation.observe(\.queuePriority, options: [.new]) { op, _ in
            if op.queuePriority == .high {
                expectation.fulfill()
            }
        }
        image.priority = .high
        await expectation.wait()
        withExtendedLifetime(kvoObserver) {}
    }

    // MARK: - Publisher

    @Test func publisherImageLoaded() async throws {
        let expectation = TestExpectation()
        let cancellable = image.$result.dropFirst().sink { _ in
            expectation.fulfill()
        }

        image.load(pipeline.imagePublisher(with: Test.request))
        await expectation.wait()

        let result = try #require(image.result)
        #expect(result.isSuccess)
        #expect(image.image != nil)
        withExtendedLifetime(cancellable) {}
    }

    @Test func publisherIsLoadingUpdated() async {
        #expect(!image.isLoading)

        let expectation = TestExpectation()
        let cancellable = image.$result.dropFirst().sink { _ in
            expectation.fulfill()
        }

        image.load(pipeline.imagePublisher(with: Test.request))
        #expect(image.isLoading)

        await expectation.wait()
        #expect(!image.isLoading)
        withExtendedLifetime(cancellable) {}
    }

    @Test func publisherMemoryCacheLookup() throws {
        pipeline.cache[Test.request] = Test.container

        image.load(pipeline.imagePublisher(with: Test.request))

        let result = try #require(image.result)
        #expect(result.isSuccess)
        let response = try #require(result.value)
        #expect(response.cacheType == .memory)
        #expect(image.image != nil)
    }

    // MARK: - Cancellation

    @Test func requestCancelledWhenTargetGetsDeallocated() async {
        dataLoader.isSuspended = true

        var localImage: FetchImage? = FetchImage()
        localImage!.pipeline = pipeline

        let startExpectation = TestExpectation(notification: ImagePipelineObserver.didStartTask, object: observer)
        localImage!.load(pipeline.imagePublisher(with: Test.request))
        await startExpectation.wait()

        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            localImage = nil
        }
    }
}
