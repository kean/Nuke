// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Combine
@testable import Nuke
@testable import NukeUI

@Suite(.timeLimit(.minutes(5))) @MainActor
struct FetchImageTests {
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

    @Test func imageLoadedViaURL() async throws {
        let expectation = TestExpectation()
        image.onCompletion = { _ in expectation.fulfill() }
        image.load(Test.url)
        await expectation.wait()

        let result = try #require(image.result)
        #expect(result.isSuccess)
        #expect(image.image != nil)
    }

    @Test func nilURLFailsWithRequestMissing() async throws {
        let expectation = TestExpectation()
        var capturedError: Error?
        image.onCompletion = { result in
            if case .failure(let error) = result { capturedError = error }
            expectation.fulfill()
        }
        image.load(nil as URL?)
        await expectation.wait()

        let error = try #require(capturedError as? ImagePipeline.Error)
        #expect(error == .imageRequestMissing)
        #expect(image.image == nil)
        #expect(!image.isLoading)
    }

    @Test func nilRequestFailsWithRequestMissing() async throws {
        let expectation = TestExpectation()
        var capturedError: Error?
        image.onCompletion = { result in
            if case .failure(let error) = result { capturedError = error }
            expectation.fulfill()
        }
        image.load(nil as ImageRequest?)
        await expectation.wait()

        let error = try #require(capturedError as? ImagePipeline.Error)
        #expect(error == .imageRequestMissing)
    }

    @Test func onStartCalled() async throws {
        dataLoader.isSuspended = true

        let expectation = TestExpectation()
        var capturedTask: ImageTask?
        image.onStart = { task in
            capturedTask = task
            expectation.fulfill()
        }
        image.load(Test.request)
        await expectation.wait()

        _ = try #require(capturedTask)
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

        let expectation = await TestExpectation(queue: queue, count: 1)

        image.priority = .high
        image.load(Test.request)

        await expectation.wait()

        let operation = try #require(expectation.operations.first)
        let priority = await operation.priority
        #expect(priority == .high)
    }

    @Test func priorityUpdatedDynamically() async throws {
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let expectation = await TestExpectation(queue: queue, count: 1)
        image.load(Test.request)
        await expectation.wait()

        let operation = try #require(expectation.operations.first)

        await queue.waitForPriorityChange(of: operation, to: .high) { @Sendable in
            Task { @MainActor in
                image.priority = .high
            }
        }
    }

    // MARK: - Progress

    @Test func progressLazilyAllocatedAndStable() {
        let progress1 = image.progress
        let progress2 = image.progress
        #expect(progress1 === progress2)
    }

    @Test func progressFractionWhenTotalIsZero() {
        let progress = FetchImage.Progress()
        #expect(progress.fraction == 0)
    }

    @Test func progressFractionMidLoad() {
        let progress = FetchImage.Progress()
        progress.total = 100
        progress.completed = 25
        #expect(progress.fraction == 0.25)
    }

    @Test func progressFractionClampedToOne() {
        let progress = FetchImage.Progress()
        progress.total = 100
        progress.completed = 150
        #expect(progress.fraction == 1)
    }

    @Test func progressIsReportedDuringLoad() async {
        dataLoader.isSuspended = true
        dataLoader.results[Test.url] = .success((
            Data(count: 20),
            URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil)
        ))

        let expectation = TestExpectation()
        image.onCompletion = { _ in expectation.fulfill() }
        image.load(Test.request)

        // Allocate progress after load() — the internal reset() clears any prior allocation.
        _ = image.progress

        dataLoader.isSuspended = false
        await expectation.wait()

        #expect(image.progress.completed == 20)
        #expect(image.progress.total == 20)
        #expect(image.progress.fraction == 1)
    }

    // MARK: - Progressive Decoding

    @Test func progressivePreviewIsDisplayed() async throws {
        let progressiveLoader = MockProgressiveDataLoader()
        let progressivePipeline = ImagePipeline {
            $0.dataLoader = progressiveLoader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.imageProcessingQueue.maxConcurrentOperationCount = 1
        }
        image.pipeline = progressivePipeline

        let previewExpectation = TestExpectation()
        let sawPreview = Mutex(wrappedValue: false)
        let cancellable = image.$imageContainer.dropFirst().sink { container in
            if container?.isPreview == true {
                let alreadySaw = sawPreview.withLock { value -> Bool in
                    let prev = value
                    value = true
                    return prev
                }
                if !alreadySaw { previewExpectation.fulfill() }
            }
            // Drive the next chunk for every container update.
            progressiveLoader.resume()
        }

        let completionExpectation = TestExpectation()
        image.onCompletion = { _ in completionExpectation.fulfill() }
        image.load(Test.request)

        await previewExpectation.wait()
        await completionExpectation.wait()

        #expect(sawPreview.withLock { $0 })
        #expect(image.imageContainer != nil)
        #expect(image.imageContainer?.isPreview == false)
        withExtendedLifetime(cancellable) {}
    }

    // MARK: - Async/Await

    @Test func asyncLoadSucceeds() async throws {
        let expectation = TestExpectation()
        image.onCompletion = { _ in expectation.fulfill() }
        image.load { Test.response }
        await expectation.wait()

        let result = try #require(image.result)
        #expect(result.isSuccess)
        #expect(image.image != nil)
        #expect(!image.isLoading)
    }

    @Test func asyncLoadFails() async throws {
        struct LoadError: Error {}

        let expectation = TestExpectation()
        image.onCompletion = { _ in expectation.fulfill() }
        image.load { throw LoadError() }
        await expectation.wait()

        let result = try #require(image.result)
        #expect(result.isFailure)
        #expect(result.error is LoadError)
        #expect(image.image == nil)
        #expect(!image.isLoading)
    }

    @Test func asyncLoadIsLoadingUpdated() async {
        #expect(!image.isLoading)
        let expectation = TestExpectation()
        image.onCompletion = { _ in expectation.fulfill() }
        image.load { Test.response }
        #expect(image.isLoading)

        await expectation.wait()
        #expect(!image.isLoading)
    }

    @Test func asyncLoadCancelledByReset() async {
        let started = TestExpectation()
        image.load {
            started.fulfill()
            try await Task.sleep(for: .seconds(60))
            return Test.response
        }
        await started.wait()
        #expect(image.isLoading)

        image.reset()

        #expect(!image.isLoading)
        #expect(image.result == nil)
    }

    // MARK: - Processors

    @Test func processorsAppliedFromImage() async {
        image.processors = [MockImageProcessor(id: "p1")]

        let expectation = TestExpectation()
        image.onCompletion = { _ in expectation.fulfill() }
        image.load(Test.request)
        await expectation.wait()

        #expect(image.imageContainer?.image.nk_test_processorIDs == ["p1"])
    }

    @Test func processorsFromRequestTakePrecedenceOverImageProcessors() async {
        image.processors = [MockImageProcessor(id: "p1")]
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p2")])

        let expectation = TestExpectation()
        image.onCompletion = { _ in expectation.fulfill() }
        image.load(request)
        await expectation.wait()

        #expect(image.imageContainer?.image.nk_test_processorIDs == ["p2"])
    }

    // MARK: - LazyImageState Protocol

    @Test func errorReturnsErrorWhenFailed() async {
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))

        let expectation = TestExpectation()
        image.onCompletion = { _ in expectation.fulfill() }
        image.load(Test.request)
        await expectation.wait()

        let state: any LazyImageState = image
        #expect(state.error != nil)
        #expect(state.image == nil)
    }

    @Test func errorReturnsNilWhenSuccessful() async {
        let expectation = TestExpectation()
        image.onCompletion = { _ in expectation.fulfill() }
        image.load(Test.request)
        await expectation.wait()

        let state: any LazyImageState = image
        #expect(state.error == nil)
        #expect(state.image != nil)
    }

    // MARK: - Reset

    @Test func resetClearsAllState() async {
        // Load an image first so there's state to clear.
        let expectation = TestExpectation()
        image.onCompletion = { _ in expectation.fulfill() }
        image.load(Test.request)
        await expectation.wait()

        #expect(image.imageContainer != nil)
        #expect(image.result != nil)

        // Touch progress so its allocation is exercised by reset.
        _ = image.progress

        image.reset()

        #expect(image.imageContainer == nil)
        #expect(image.result == nil)
        #expect(!image.isLoading)
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
