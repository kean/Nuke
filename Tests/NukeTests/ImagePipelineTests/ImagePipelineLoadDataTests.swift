// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineLoadDataTests {
    let dataLoader: MockDataLoader
    let dataCache: MockDataCache
    let pipeline: ImagePipeline
    let encoder: MockImageEncoder

    init() {
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let encoder = MockImageEncoder(result: Test.data)
        self.dataLoader = dataLoader
        self.dataCache = dataCache
        self.encoder = encoder
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.makeImageEncoder = { _ in encoder }
        }
    }

    @Test func loadDataDataLoaded() async throws {
        let (data, _) = try await pipeline.data(for: Test.request)
        #expect(data.count == 22789)
    }

    // MARK: - Progress Reporting

    @Test func progressClosureIsCalled() async throws {
        // Given
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let task = pipeline.imageTask(with: Test.url)
        var progressValues: [ImageTask.Progress] = []
        for await progress in task.progress {
            progressValues.append(progress)
        }
        _ = try? await task.response

        // Then
        #expect(progressValues == [
            ImageTask.Progress(completed: 10, total: 20),
            ImageTask.Progress(completed: 20, total: 20)
        ])
    }

    // MARK: - Chunked Responses

    // The loader calls back on its own thread, and the pipeline applies the
    // callbacks on its actor in batches. A batch must not reorder the chunks,
    // let the completion overtake them, or apply them to a cancelled task.

    @Test func chunksAreAppliedInOrder() async throws {
        // GIVEN a loader that delivers each response in 1000 chunks back to
        // back from a background queue, and then completes
        dataLoader.chunkCount = 1000

        // WHEN loading a number of responses at once
        let pipeline = self.pipeline
        try await withThrowingTaskGroup(of: Data.self) { group in
            for index in 0..<20 {
                group.addTask {
                    try await pipeline.data(for: ImageRequest(url: URL(string: "http://test.com/\(index)"))).0
                }
            }
            // THEN each response is its chunks concatenated in order; a chunk
            // applied out of order, or dropped after the completion, breaks it
            for try await data in group {
                #expect(data == Test.data)
            }
        }
    }

    @Test func progressIsReportedForEveryChunkBeforeCompletion() async throws {
        // GIVEN a loader that delivers the response in 1000 chunks
        dataLoader.chunkCount = 1000
        let observer = ImagePipelineObserver()
        let pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        // WHEN
        let completed = TestExpectation(notification: ImagePipelineObserver.didCompleteTask, object: observer)
        _ = try await pipeline.imageTask(with: Test.request).response
        await completed.wait()

        // THEN progress is reported once per chunk, in order
        let total = Int64(Test.data.count)
        let chunkSize = total / 1000
        let expected = (1...1000).map {
            ImageTaskEvent.progressUpdated(completedUnitCount: $0 == 1000 ? total : Int64($0) * chunkSize, totalUnitCount: total)
        }
        #expect(observer.events.filter(\.isProgress) == expected)

        // THEN the task completes after the last chunk
        guard case .completed(result: .success) = observer.events.last else {
            Issue.record("Expected the task to complete last, got \(String(describing: observer.events.last))")
            return
        }
    }

    @Test @ImagePipelineActor func failureIsReportedAfterTheChunksBeforeIt() async throws {
        // GIVEN a loader that delivers part of the response and then fails
        let dataLoader = ManualDataLoader()
        let observer = ImagePipelineObserver()
        let pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let task = pipeline.imageTask(with: Test.request)
        await dataLoader.started.wait()

        // WHEN the chunks and the failure arrive while the test holds the
        // actor, so the pipeline applies them in a single batch
        let completed = TestExpectation(notification: ImagePipelineObserver.didCompleteTask, object: observer)
        let chunks = _createChunks(for: Test.data, size: Test.data.count / 4).dropLast()
        for chunk in chunks {
            dataLoader.serve(chunk)
        }
        dataLoader.complete(with: URLError(.networkConnectionLost))

        // THEN the task fails with the loader's error
        do {
            _ = try await task.response
            Issue.record("Expected failure")
        } catch {
            #expect((error.dataLoadingError as? URLError)?.code == .networkConnectionLost)
        }
        await completed.wait()

        // THEN progress is reported for every chunk before the failure
        #expect(observer.events.filter(\.isProgress).count == chunks.count)
        guard case .completed(result: .failure) = observer.events.last else {
            Issue.record("Expected the task to fail last, got \(String(describing: observer.events.last))")
            return
        }
    }

    @Test @ImagePipelineActor func cancellingWhileChunksWaitForTheActor() async throws {
        // GIVEN a load in progress, and a data loading queue with one slot
        let dataLoader = ManualDataLoader()
        let observer = ImagePipelineObserver()
        let pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 1)
        }
        let task = pipeline.imageTask(with: Test.request)
        await dataLoader.started.wait()

        // WHEN chunks arrive while the test holds the actor, so they can't be
        // applied yet, and the task is cancelled
        for chunk in _createChunks(for: Test.data, size: Test.data.count / 4) {
            dataLoader.serve(chunk)
        }
        task._cancelTask()

        // THEN the task is cancelled without receiving any of them
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }
        #expect(observer.events == [.created, .started, .cancelled])
        #expect(dataLoader.isCancelled)

        // THEN the load still finishes, releasing its slot in the queue
        await pipeline.configuration.dataLoadingQueue.waitUntilAllOperationsAreFinished()
    }

    @Test @ImagePipelineActor func cancellingInTheMiddleOfABatch() async throws {
        // GIVEN a delegate that cancels the task when it reports progress
        let dataLoader = ManualDataLoader()
        let delegate = CancelOnProgressDelegate()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 1)
        }
        let task = pipeline.imageTask(with: Test.request)
        await dataLoader.started.wait()

        // WHEN the whole response arrives while the test holds the actor, so
        // the pipeline applies it in a single batch
        let chunks = _createChunks(for: Test.data, size: Test.data.count / 4)
        for chunk in chunks {
            dataLoader.serve(chunk)
        }
        dataLoader.complete(with: nil)

        // THEN the task is cancelled on the first chunk and receives nothing
        // from the rest of the batch
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }
        #expect(delegate.progress == [ImageTask.Progress(completed: Int64(chunks[0].count), total: Int64(Test.data.count))])

        // THEN the load still finishes, releasing its slot in the queue
        await pipeline.configuration.dataLoadingQueue.waitUntilAllOperationsAreFinished()
    }

    // MARK: - Errors

    @Test func loadWithInvalidURL() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataLoader = DataLoader()
        }

        // WHEN/THEN
        do {
            _ = try await pipeline.data(for: ImageRequest(url: URL(string: "")))
            Issue.record("Expected failure")
        } catch {
            // Expected
        }
    }

    @Test func downloadExceedingMaximumResponseDataSize() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.maximumResponseDataSize = 1024
        }

        // WHEN/THEN
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Expected failure")
        } catch {
            guard case .dataDownloadExceededMaximumSize = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    /// When the server doesn't report the size upfront, the limit is enforced
    /// against the data received so far.
    @Test func downloadExceedingMaximumResponseDataSizeWithUnknownContentLength() async throws {
        // GIVEN a response with no `expectedContentLength`
        let response = URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: -1, textEncodingName: nil)
        dataLoader.results[Test.url] = .success((Test.data, response))
        let pipeline = pipeline.reconfigured {
            $0.maximumResponseDataSize = 1024
        }

        // WHEN/THEN
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Expected failure")
        } catch {
            guard case .dataDownloadExceededMaximumSize = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    // MARK: - ImageRequest.CachePolicy

    @Test func cacheLookupWithDefaultPolicyImageStored() async throws {
        // GIVEN
        pipeline.cache.storeCachedImage(Test.container, for: Test.request)

        // WHEN
        _ = try await pipeline.data(for: Test.request)

        // THEN
        #expect(dataCache.readCount == 1)
        #expect(dataCache.writeCount == 1) // Initial write
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func cacheLookupWithReloadPolicyImageStored() async throws {
        // GIVEN
        pipeline.cache.storeCachedImage(Test.container, for: Test.request)

        // WHEN
        let request = ImageRequest(url: Test.url, options: [.reloadIgnoringCachedData])
        _ = try await pipeline.data(for: request)

        // THEN
        #expect(dataCache.readCount == 0)
        #expect(dataCache.writeCount == 2) // Initial write + write after fetch
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - DataCachePolicy

    // MARK: DataCachPolicy.automatic

    @Test func policyAutomaticGivenRequestWithProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN nothing is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    @Test func policyAutomaticGivenRequestWithoutProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyAutomaticGivenTwoRequests() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // WHEN
        _ = try await pipeline.data(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        _ = try await pipeline.data(for: ImageRequest(url: Test.url))

        // THEN
        // only original image is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    // MARK: DataCachPolicy.storeOriginalData

    @Test func policyStoreOriginalDataGivenRequestWithProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN nothing is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreOriginalDataGivenRequestWithoutProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreOriginalDataGivenTwoRequests() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // WHEN
        _ = try await pipeline.data(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        _ = try await pipeline.data(for: ImageRequest(url: Test.url))

        // THEN
        // only original image is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    // MARK: DataCachPolicy.storeEncodedImages

    @Test func policyStoreEncodedImagesGivenRequestWithProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN nothing is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) == nil)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    @Test func policyStoreEncodedImagesGivenRequestWithoutProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) == nil)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    @Test func policyStoreEncodedImagesGivenTwoRequests() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // WHEN
        _ = try await pipeline.data(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        _ = try await pipeline.data(for: ImageRequest(url: Test.url))

        // THEN
        // only original image is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) == nil)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    // MARK: DataCachPolicy.storeAll

    @Test func policyStoreAllGivenRequestWithProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN nothing is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreAllGivenRequestWithoutProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreAllGivenTwoRequests() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // WHEN
        _ = try await pipeline.data(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        _ = try await pipeline.data(for: ImageRequest(url: Test.url))

        // THEN
        // only original image is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }
}

private extension ImageTaskEvent {
    var isProgress: Bool {
        if case .progressUpdated = self { true } else { false }
    }
}

/// Hands the test the callbacks of the load it starts, so that the test
/// decides when, and from which thread, the response arrives.
private final class ManualDataLoader: DataLoading, Sendable {
    private struct Callbacks: Sendable {
        let didReceiveData: @Sendable (Data, URLResponse) -> Void
        let completion: @Sendable ((any Error)?) -> Void
    }

    let started = TestExpectation()
    var isCancelled: Bool { _isCancelled.withLock { $0 } }

    private let _isCancelled = OSAllocatedUnfairLock(initialState: false)
    private let callbacks = OSAllocatedUnfairLock<Callbacks?>(initialState: nil)

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable ((any Error)?) -> Void) -> any Cancellable {
        callbacks.withLock { $0 = Callbacks(didReceiveData: didReceiveData, completion: completion) }
        started.fulfill()
        return AnonymousCancellable { [self] in
            _isCancelled.withLock { $0 = true }
            // `URLSession` reports a cancelled load through its completion.
            complete(with: URLError(.cancelled))
        }
    }

    func serve(_ chunk: Data) {
        callbacks.withLock { $0 }?.didReceiveData(chunk, Test.urlResponse)
    }

    /// Completes the load and, like `URLSession`, lets go of its callbacks.
    func complete(with error: (any Error)?) {
        callbacks.withLock { $0.take() }?.completion(error)
    }
}

/// Cancels a task from inside the event that reports its progress.
@ImagePipelineActor
private final class CancelOnProgressDelegate: ImagePipeline.Delegate {
    private(set) var progress: [ImageTask.Progress] = []

    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        guard case .progress(let value) = event else { return }
        progress.append(value)
        task._cancelTask()
    }
}
