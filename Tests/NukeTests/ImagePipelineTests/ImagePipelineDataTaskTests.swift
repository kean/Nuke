// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

/// `ImagePipeline/data(for:)`: the data tasks (`TaskLoadData`) and the fetch of
/// the original data they share with the image tasks (`TaskFetchOriginalData`).
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDataTaskTests {
    private let dataLoader: MockDataLoader
    private let dataCache: MockDataCache
    private let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        self.dataLoader = dataLoader
        self.dataCache = dataCache
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
        }
    }

    // MARK: - Loading

    @Test func dataIsReturnedAlongWithTheLoaderResponse() async throws {
        // GIVEN a response delivered in two chunks
        let urlResponse = try #require(HTTPURLResponse(url: Test.url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Length": "\(Test.data.count)",
            "X-Request-ID": "42"
        ]))
        dataLoader.results[Test.url] = .success((Test.data, urlResponse))

        // WHEN
        let (data, response) = try await pipeline.data(for: Test.request)

        // THEN the chunks are put back together in order
        #expect(data == Test.data)
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse === urlResponse)
        #expect(httpResponse.value(forHTTPHeaderField: "X-Request-ID") == "42")
    }

    /// A data task has no use for an image, so it neither decodes nor
    /// processes anything – even data that isn't an image is returned as is.
    @Test func dataIsNeitherDecodedNorProcessed() async throws {
        // GIVEN data that isn't an image and a request with a processor
        let bytes = Data("not an image".utf8)
        dataLoader.results[Test.url] = .success((bytes, URLResponse(url: Test.url, mimeType: "text/plain", expectedContentLength: bytes.count, textEncodingName: nil)))
        let processors = MockProcessorFactory()
        let request = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])

        // WHEN
        let (data, _) = try await pipeline.data(for: request)

        // THEN
        #expect(data == bytes)
        #expect(processors.numberOfProcessorsApplied == 0)
    }

    /// The data of a thumbnail request is the original image, and it's stored
    /// in the disk cache as the original, under the key without the thumbnail.
    @Test func thumbnailRequestReturnsAndStoresTheOriginalData() async throws {
        // GIVEN
        var request = Test.request
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 40)

        // WHEN
        let (data, _) = try await pipeline.data(for: request)

        // THEN
        #expect(data == Test.data)
        #expect(dataCache.store == [Test.url.absoluteString: Test.data])
    }

    // MARK: - Data Cache

    @Test func cachedDataIsReturnedWithoutAResponse() async throws {
        // GIVEN data in the disk cache that isn't even an image
        let bytes = Data("cached".utf8)
        dataCache.store[Test.url.absoluteString] = bytes

        // WHEN
        let (data, response) = try await pipeline.data(for: Test.request)

        // THEN
        #expect(data == bytes)
        #expect(response == nil)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func disableDiskCacheReadsLoadsTheDataAgain() async throws {
        // GIVEN stale data in the disk cache
        dataCache.store[Test.url.absoluteString] = Data("stale".utf8)

        // WHEN
        let (data, _) = try await pipeline.data(for: ImageRequest(url: Test.url, options: [.disableDiskCacheReads]))

        // THEN the fresh data is returned and replaces the stale one
        #expect(data == Test.data)
        #expect(dataLoader.createdTaskCount == 1)
        #expect(dataCache.store[Test.url.absoluteString] == Test.data)
    }

    // MARK: - Errors

    /// The emptiness check comes before the disk cache: empty data is never
    /// stored.
    @Test func emptyResponseFailsWithDataIsEmptyAndIsNotStored() async throws {
        // GIVEN
        dataLoader.results[Test.url] = .success((Data(), Test.urlResponse))

        // WHEN/THEN
        await #expect(throws: ImagePipeline.Error.dataIsEmpty) {
            try await pipeline.data(for: Test.request)
        }
        #expect(dataCache.writeCount == 0)
    }

    @Test func emptyClosureDataFailsWithDataIsEmptyAndIsNotStored() async throws {
        // GIVEN
        let request = ImageRequest(id: "empty", data: { Data() })

        // WHEN/THEN
        await #expect(throws: ImagePipeline.Error.dataIsEmpty) {
            try await pipeline.data(for: request)
        }
        #expect(dataCache.writeCount == 0)
    }

    /// A request for an image container has no data to return.
    @Test func imageClosureRequestFailsToLoadData() async throws {
        // GIVEN
        let request = ImageRequest(id: "image", image: { Test.container })

        // WHEN/THEN
        do {
            _ = try await pipeline.data(for: request)
            Issue.record("Expected the request to fail")
        } catch {
            guard case .dataLoadingFailed = error else {
                Issue.record("Expected dataLoadingFailed, got \(error)")
                return
            }
        }
        #expect(dataLoader.createdTaskCount == 0)
    }

    // MARK: - Maximum Response Data Size

    /// The limit is inclusive: a response of exactly the maximum size is fine.
    @Test(arguments: [Int64(22789), -1])
    func responseOfExactlyTheMaximumSizeIsAccepted(expectedContentLength: Int64) async throws {
        // GIVEN
        let response = URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: Int(expectedContentLength), textEncodingName: nil)
        dataLoader.results[Test.url] = .success((Test.data, response))
        let pipeline = pipeline.reconfigured {
            $0.maximumResponseDataSize = Test.data.count
        }

        // WHEN
        let (data, _) = try await pipeline.data(for: Test.request)

        // THEN
        #expect(data == Test.data)
    }

    @Test(arguments: [Int64(22789), -1])
    func responseOneByteOverTheMaximumSizeIsRejected(expectedContentLength: Int64) async throws {
        // GIVEN
        let response = URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: Int(expectedContentLength), textEncodingName: nil)
        dataLoader.results[Test.url] = .success((Test.data, response))
        let pipeline = pipeline.reconfigured {
            $0.maximumResponseDataSize = Test.data.count - 1
        }

        // WHEN/THEN
        await #expect(throws: ImagePipeline.Error.dataDownloadExceededMaximumSize) {
            try await pipeline.data(for: Test.request)
        }
    }

    /// A response that advertises more than the default limit (at most 200 MB)
    /// is rejected up front – unless the limit is disabled with `nil`.
    @Test func maximumResponseDataSizeCanBeDisabled() async throws {
        // GIVEN a response that advertises more than the default limit
        let advertisedSize = 210 * 1024 * 1024
        let defaultLimit = try #require(pipeline.configuration.maximumResponseDataSize)
        #expect(defaultLimit < advertisedSize)
        let response = URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: advertisedSize, textEncodingName: nil)
        dataLoader.results[Test.url] = .success((Test.data, response))

        // WHEN/THEN the default limit rejects it
        await #expect(throws: ImagePipeline.Error.dataDownloadExceededMaximumSize) {
            try await pipeline.data(for: Test.request)
        }

        // WHEN/THEN no limit lets it through
        let unlimited = pipeline.reconfigured {
            $0.maximumResponseDataSize = nil
        }
        let (data, _) = try await unlimited.data(for: Test.request)
        #expect(data == Test.data)
    }

    /// The docs: "The maximum response data size in bytes allowed before the
    /// download is automatically cancelled".
    @Test(arguments: [Int64(4096 * 4), -1])
    func downloadExceedingTheMaximumSizeIsCancelled(expectedContentLength: Int64) async throws {
        // GIVEN a limit below the size of the response
        let loader = _ScriptedDataLoader(chunks: Array(repeating: Data(count: 4096), count: 4), expectedContentLength: Int(expectedContentLength))
        let pipeline = ImagePipeline {
            $0.dataLoader = loader
            $0.imageCache = nil
            $0.maximumResponseDataSize = 4096 * 2
        }

        // WHEN/THEN
        await #expect(throws: ImagePipeline.Error.dataDownloadExceededMaximumSize) {
            try await pipeline.data(for: Test.request)
        }
        #expect(loader.cancelCount == 1)
    }

    // MARK: - Custom Data Closure

    @Test func closureDataIsReturnedWithoutAResponse() async throws {
        // GIVEN
        let bytes = Data("closure".utf8)
        let request = ImageRequest(id: "closure", data: { bytes })

        // WHEN
        let (data, response) = try await pipeline.data(for: request)

        // THEN
        #expect(data == bytes)
        #expect(response == nil)
        #expect(dataLoader.createdTaskCount == 0)
    }

    /// The docs: "If the pipeline uses a DataCaching disk cache, the fetched
    /// data will be stored in it".
    @Test func closureDataIsStoredInTheDataCacheUnderTheID() async throws {
        // GIVEN
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let request = ImageRequest(id: "photo-1", data: {
            calls.withLock { $0 += 1 }
            return Test.data
        })

        // WHEN the data is requested twice
        _ = try await pipeline.data(for: request)
        let (data, _) = try await pipeline.data(for: request)

        // THEN the second request is served by the disk cache
        #expect(dataCache.store["photo-1"] == Test.data)
        #expect(data == Test.data)
        #expect(calls.withLock { $0 } == 1)
    }

    /// The docs: "Use disableDiskCache to prevent this".
    @Test func closureDataIsNotStoredWithDisableDiskCache() async throws {
        // GIVEN
        let request = ImageRequest(id: "photo-1", data: { Test.data }, options: [.disableDiskCache])

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.isEmpty)
    }

    @Test func closureRequestsWithTheSameIDAreCoalesced() async throws {
        // GIVEN a closure that waits until both requests join
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let proceed = AsyncGate()
        @Sendable func makeRequest() -> ImageRequest {
            ImageRequest(id: "photo-1", data: {
                calls.withLock { $0 += 1 }
                await proceed.wait()
                return Test.data
            })
        }

        // WHEN
        let started = TestExpectation()
        let startCount = OSAllocatedUnfairLock(initialState: 0)
        pipeline.onTaskStarted = { _ in
            if startCount.withLock({ $0 += 1; return $0 }) == 2 { started.fulfill() }
        }
        let task1 = pipeline.makeStartedImageTask(with: makeRequest(), isDataTask: true)
        let task2 = pipeline.makeStartedImageTask(with: makeRequest(), isDataTask: true)
        await started.wait()
        proceed.open()

        // THEN the closure runs once and both get the data
        #expect(try await task1.response.container.data == Test.data)
        #expect(try await task2.response.container.data == Test.data)
        #expect(calls.withLock { $0 } == 1)
    }

    /// The closure runs in a `Task` that is cancelled along with the request,
    /// so a closure that supports cancellation stops early.
    @Test(arguments: [false, true])
    func cancellationReachesTheClosure(skipDataLoadingQueue: Bool) async throws {
        // GIVEN a closure that runs until it is cancelled
        let entered = TestExpectation()
        let cancelled = TestExpectation()
        let request = ImageRequest(
            id: "never-ending",
            data: {
                let gate = AsyncGate()
                await withTaskCancellationHandler {
                    entered.fulfill()
                    await gate.wait()
                } onCancel: {
                    cancelled.fulfill()
                    gate.open()
                }
                return Test.data
            },
            options: skipDataLoadingQueue ? [.skipDataLoadingQueue] : []
        )

        // WHEN
        let task = pipeline.makeStartedImageTask(with: request, isDataTask: true)
        await entered.wait()
        task.cancel()

        // THEN
        await cancelled.wait()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }
    }

    // MARK: - Cancellation

    @Test func cancellingTheDataTaskCancelsTheDownload() async throws {
        // GIVEN a download in flight
        dataLoader.isSuspended = true
        let started = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.makeStartedImageTask(with: Test.request, isDataTask: true)
        await started.wait()

        // WHEN/THEN
        await notification(MockDataLoader.DidCancelTask, object: dataLoader) {
            task.cancel()
        }
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }
        #expect(dataCache.writeCount == 0)
    }

    @Test func cancellingOneOfTwoDataTasksLeavesTheDownloadRunning() async throws {
        // GIVEN two data tasks waiting for the same download
        dataLoader.isSuspended = true
        let started = TestExpectation()
        let startCount = OSAllocatedUnfairLock(initialState: 0)
        pipeline.onTaskStarted = { _ in
            if startCount.withLock({ $0 += 1; return $0 }) == 2 { started.fulfill() }
        }
        let task1 = pipeline.makeStartedImageTask(with: Test.request, isDataTask: true)
        let task2 = pipeline.makeStartedImageTask(with: Test.request, isDataTask: true)
        await started.wait()

        // WHEN one of them is cancelled
        task1.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task1.response
        }
        dataLoader.isSuspended = false

        // THEN the other still gets the data from the same download
        #expect(try await task2.response.container.data == Test.data)
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Events

    /// `TaskLoadData` forwards the progress of the download, but not the
    /// partial data: a data task has no previews, even when the pipeline
    /// decodes progressively.
    @Test func dataTaskReportsProgressButNoPreviews() async throws {
        // GIVEN a progressive JPEG and progressive decoding
        let data = Test.data(name: "progressive", extension: "jpeg")
        dataLoader.results[Test.url] = .success((data, URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: data.count, textEncodingName: nil)))
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
        }

        // WHEN
        let progress = LockedArray<ImageTask.Progress>()
        let previews = LockedArray<ImageResponse>()
        let task = pipeline.makeStartedImageTask(with: Test.request, isDataTask: true) { event, _ in
            switch event {
            case .progress(let value): progress.append(value)
            case .preview(let preview): previews.append(preview)
            case .finished: break
            }
        }
        let response = try await task.response

        // THEN
        let total = Int64(data.count)
        #expect(progress.values == [
            ImageTask.Progress(completed: total / 2, total: total),
            ImageTask.Progress(completed: total, total: total)
        ])
        #expect(previews.count == 0)
        #expect(response.container.data == data)
        #expect(response.urlResponse != nil)
        #expect(task.status.progress == ImageTask.Progress(completed: total, total: total))
    }

    // MARK: - Data Loading Queue

    /// Data tasks share the data loading queue with the image tasks, and a
    /// cancelled download hands its slot over to the next one.
    ///
    /// - note: The slot is only freed once the loader calls `completion`,
    /// which the default `DataLoader` does after `cancel()` because
    /// `URLSession` reports the cancellation. A loader that stays silent
    /// after `cancel()`, as the `DataLoading` docs ask, never frees it.
    @Test func cancelledDownloadHandsItsSlotToTheNextOne() async throws {
        // GIVEN one download at a time, and a loader that reports the
        // cancellation the way `URLSession` does
        let loader = _StallingDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = loader
            $0.imageCache = nil
            $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 1)
        }
        let stalled = pipeline.imageTask(with: _StallingDataLoader.stalledURL)
        await loader.started.wait()

        // WHEN a data task is started while the only slot is taken
        let next = pipeline.makeStartedImageTask(with: Test.request, isDataTask: true)
        await Task { @ImagePipelineActor in }.value

        // THEN it waits for the slot
        #expect(await pipeline.configuration.dataLoadingQueue.operationCount == 2)
        #expect(loader.requestCount == 1)

        // WHEN the download that holds the slot is cancelled
        stalled.cancel()

        // THEN the data task gets the slot
        #expect(try await next.response.container.data == Test.data)
        #expect(loader.requestCount == 2)
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await stalled.response
        }
    }

    // MARK: - Data Loader

    /// The `DataLoading` contract forbids calling back after the completion,
    /// but a loader that does it anyway must not bring the pipeline down.
    @Test func callbacksAfterTheCompletionAreIgnored() async throws {
        // GIVEN a loader that sends another chunk and completes twice more
        // after it has completed
        let chunk = Data("chunk".utf8)
        let loader = _ScriptedDataLoader(chunks: [chunk], expectedContentLength: -1)
        loader.callsBackAfterCompletion = true
        let pipeline = ImagePipeline {
            $0.dataLoader = loader
            $0.imageCache = nil
        }

        // WHEN
        let (data, _) = try await pipeline.data(for: Test.request)

        // THEN only what was sent before the completion is returned
        #expect(data == chunk)
    }

    @Test func delegateCanTurnOffTheDataCacheForARequest() async throws {
        // GIVEN a delegate with no disk cache for requests marked as private
        let delegate = _DataLoadingDelegate()
        delegate.isDataCacheDisabled = { $0.userInfo["private"] as? Bool == true }
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
        }
        dataCache.store[Test.url.absoluteString] = Data("cached".utf8)
        var request = Test.request
        request.userInfo["private"] = true

        // WHEN
        let (data, _) = try await pipeline.data(for: request)

        // THEN the cache is neither read nor written
        #expect(data == Test.data)
        #expect(dataCache.readCount == 0)
        #expect(dataCache.writeCount == 0)
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Priority

    @Test @ImagePipelineActor func dataTaskPriorityIsAppliedToTheDownload() async throws {
        // GIVEN
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        defer { queue.isSuspended = false }
        let expectation = TestExpectation(queue: queue, count: 1)
        let task = pipeline.makeStartedImageTask(with: ImageRequest(url: Test.url, priority: .high), isDataTask: true)
        await expectation.wait()

        // THEN the download is enqueued with the priority of the request
        let operation = try #require(expectation.operations.first)
        #expect(operation.priority == .high)

        // WHEN/THEN the priority of the task changes
        await queue.waitForPriorityChange(of: operation, to: .veryLow) {
            task.priority = .veryLow
        }
        task.cancel()
    }
}

// MARK: - Helpers

/// Sends the given chunks with a single response and completes, all before
/// returning from `loadData`.
private final class _ScriptedDataLoader: DataLoading, @unchecked Sendable {
    let chunks: [Data]
    let expectedContentLength: Int
    /// Sends one more chunk and completes once more after the completion.
    var callsBackAfterCompletion = false

    var cancelCount: Int { lock.withLock { _cancelCount } }

    private let lock = NSLock()
    private var _cancelCount = 0

    init(chunks: [Data], expectedContentLength: Int) {
        self.chunks = chunks
        self.expectedContentLength = expectedContentLength
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let response = URLResponse(url: request.url!, mimeType: "image/jpeg", expectedContentLength: expectedContentLength, textEncodingName: nil)
        for chunk in chunks {
            didReceiveData(chunk, response)
        }
        completion(nil)
        if callsBackAfterCompletion {
            didReceiveData(Data("late".utf8), response)
            completion(nil)
            completion(URLError(.unknown))
        }
        return AnonymousCancellable { [weak self] in
            self?.lock.withLock { self?._cancelCount += 1 }
        }
    }
}

/// Serves `Test.data`, except for ``stalledURL``, which never responds until
/// it is cancelled, and then fails with `URLError.cancelled`, like
/// `URLSession` does.
private final class _StallingDataLoader: DataLoading, @unchecked Sendable {
    static let stalledURL = URL(string: "https://example.com/stalled.jpeg")!

    let started = TestExpectation()
    var requestCount: Int { lock.withLock { _requestCount } }

    private let lock = NSLock()
    private var _requestCount = 0

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        lock.withLock { _requestCount += 1 }
        guard request.url == Self.stalledURL else {
            didReceiveData(Test.data, URLResponse(url: request.url!, mimeType: "image/jpeg", expectedContentLength: Test.data.count, textEncodingName: nil))
            completion(nil)
            return AnonymousCancellable {}
        }
        started.fulfill()
        return AnonymousCancellable {
            completion(URLError(.cancelled))
        }
    }
}

private final class _DataLoadingDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    var isDataCacheDisabled: (ImageRequest) -> Bool = { _ in false }

    func dataCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any DataCaching)? {
        isDataCacheDisabled(request) ? nil : pipeline.configuration.dataCache
    }
}
