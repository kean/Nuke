// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// The most the download buffer reserves up front, however large the server
/// says the response is. The buffer still grows past it as the bytes arrive.
private let maximumReservedCapacity: Int64 = 64 * 1024 * 1024

/// Fetches original image from the data loader (`DataLoading`) and stores it
/// in the disk cache (`DataCaching`).
final class TaskFetchOriginalData: AsyncPipelineTask<(Data, URLResponse?)> {
    private var urlResponse: URLResponse?
    private var resumableData: ResumableData?
    private var resumedDataCount: Int64 = 0
    private var data = Data()
    private var dataLoadContinuation: UnsafeContinuation<Void, Error>?
    private var dataLoadCancellable: (any Cancellable)?
    private var dataLoadTask: Task<Void, Never>?
    /// The diagnostics stage of the download, from the moment it is enqueued.
    private var downloadStage: Int?

    override func start() {
        if case .data(let closure) = request.resource {
            loadAsyncData(closure)
            return
        }

        guard let urlRequest = request.urlRequest, let url = urlRequest.url else {
            // A malformed URL prevented a URL request from being initiated.
            send(error: .dataLoadingFailed(error: URLError(.badURL)))
            return
        }

        if url.isLocalResource && pipeline.configuration.isLocalResourcesSupportEnabled {
            let stage = diagnostics?.beginStage(.download)
            do {
                let data = try Data(contentsOf: url)
                diagnostics?.endStage(stage) {
                    $0.source = .file
                    $0.bytes = Int64(data.count)
                }
                send(value: (data, nil), isCompleted: true)
            } catch {
                diagnostics?.endStage(stage) { $0.source = .file }
                send(error: .dataLoadingFailed(error: error))
            }
            return
        }

        if let rateLimiter = pipeline.rateLimiter {
            // Rate limiter is synchronized on pipeline's queue. Delayed work is
            // executed asynchronously also on the same queue.
            let queuedAt: ContinuousClock.Instant? = diagnostics != nil ? .now : nil
            var isDeferred = false
            rateLimiter.execute { [weak self] in
                guard let self, !self.isDisposed else {
                    return false
                }
                if isDeferred, let queuedAt {
                    // The limiter held the request: `execute` returned before
                    // it ran the work.
                    self.diagnostics?.recordStage(.rateLimit, from: queuedAt)
                }
                self.loadData(urlRequest: urlRequest)
                return true
            }
            isDeferred = true
        } else { // Start loading immediately.
            loadData(urlRequest: urlRequest)
        }
    }

    private func loadData(urlRequest: URLRequest) {
        downloadStage = diagnostics?.beginStage(.download, queued: true)
        if request.options.contains(.skipDataLoadingQueue) {
            dataLoadTask = Task { @ImagePipelineActor in
                await self.performDataLoad(urlRequest: urlRequest)
            }
            onCancelled = { [weak self] in
                self?.dataLoadTask?.cancel()
            }
        } else {
            // Wrap data request in an operation to limit the maximum number of
            // concurrent data tasks.
            operation = pipeline.configuration.dataLoadingQueue.add(priority: priority) { [weak self] in
                guard let self else { return }
                await self.performDataLoad(urlRequest: urlRequest)
            }
        }
    }

    private func performDataLoad(urlRequest: URLRequest) async {
        guard !isDisposed else { return }

        // Read and remove resumable data from cache (we're going to insert it
        // back in the cache if the request fails to complete again).
        var urlRequest = urlRequest
        if pipeline.configuration.isResumableDataEnabled,
           let resumableData = ResumableDataStorage.shared.removeResumableData(for: request, pipeline: pipeline) {
            // Update headers to add "Range" and "If-Range" headers
            resumableData.resume(request: &urlRequest)
            // Save resumable data to be used later (before using it, the pipeline
            // verifies that the server returns "206 Partial Content")
            self.resumableData = resumableData
        }

        onCancelled = { [weak self] in
            guard let self else { return }
            self.dataLoadTask?.cancel()
            self.dataLoadCancellable?.cancel()
            self.tryToSaveResumableData()
            // A loader doesn't have to call the completion after `cancel()`,
            // so resume here to give back the data loading queue slot.
            self.finishDataLoad(error: CancellationError())
        }

        let dataLoader = pipeline.delegate.dataLoader(for: request, pipeline: pipeline)

        do {
            let willLoadDataStage = pipeline.isDefaultDelegate ? nil : diagnostics?.beginStage(.willLoadData)
            do {
                urlRequest = try await pipeline.willLoadData(for: request, urlRequest: urlRequest)
            } catch {
                diagnostics?.endStage(willLoadDataStage)
                throw error
            }
            diagnostics?.endStage(willLoadDataStage)
            // The task can get cancelled while the delegate is suspended.
            // `onCancelled` already ran, so there is nothing left to clean up.
            guard !isDisposed else { return }

            diagnostics?.startStage(downloadStage)
            try await loadData(with: urlRequest, dataLoader: dataLoader)
            await dataTaskDidFinish()
        } catch {
            if let error = error as? ImagePipeline.Error {
                await dataTaskDidFinish(error: error)
            } else {
                await dataTaskDidFinish(error: .dataLoadingFailed(error: error))
            }
        }
    }

    // This method was previously using `AsyncThrowingStream` but it turned out to be
    // sub-optimal in terms of the performance.
    private func loadData(with urlRequest: URLRequest, dataLoader: any DataLoading) async throws {
        try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, Error>) in
            dataLoadContinuation = continuation
            let didReceiveData: @Sendable (Data, URLResponse) -> Void = { [weak self] chunk, response in
                Task { @ImagePipelineActor in
                    self?.dataTaskDidReceive(chunk: chunk, response: response)
                }
            }
            // Each branch passes its own completion so that the common one
            // isn't wrapped in a closure that only exists to drop the metrics.
            if downloadStage != nil, let dataLoader = dataLoader as? DataLoader {
                // The diagnostics are on: ask for what `URLSession` measured.
                dataLoadCancellable = dataLoader.loadData(with: urlRequest, didReceiveData: didReceiveData) { [weak self] error, metrics in
                    Task { @ImagePipelineActor in
                        self?.finishDataLoad(error: error, urlSessionMetrics: metrics)
                    }
                }
                if let handle = dataLoadCancellable as? URLSessionTaskCancellable {
                    diagnostics?.updateStage(downloadStage) { $0.urlSessionTaskID = handle.task.taskIdentifier }
                }
            } else {
                dataLoadCancellable = dataLoader.loadData(with: urlRequest, didReceiveData: didReceiveData) { [weak self] error in
                    Task { @ImagePipelineActor in
                        self?.finishDataLoad(error: error)
                    }
                }
            }
        }
    }

    private func dataTaskDidReceive(chunk: Data, response: URLResponse) {
        guard dataLoadContinuation != nil, !isDisposed else { return }
        diagnostics?.recordFirstByte(downloadStage, statusCode: (response as? HTTPURLResponse)?.statusCode)
        do {
            if urlResponse == nil {
                try dataTask(didReceiveResponse: response)
            }
            try dataTask(didReceiveData: chunk, response: response)
        } catch {
            dataLoadCancellable?.cancel()
            finishDataLoad(error: error)
        }
    }

    private func finishDataLoad(error: Swift.Error?, urlSessionMetrics: URLSessionTaskMetrics? = nil) {
        guard let continuation = dataLoadContinuation else { return }
        dataLoadContinuation = nil
        dataLoadCancellable = nil
        if let urlSessionMetrics {
            diagnostics?.updateStage(downloadStage) { stage in
                if let taskID = stage.urlSessionTaskID {
                    stage.urlSessionMetrics = .init(urlSessionMetrics, urlSessionTaskID: taskID)
                }
            }
        }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    /// Processes the initial response. Returns `false` if the size limit is
    /// exceeded early (based on expected content length).
    private func dataTask(didReceiveResponse response: URLResponse) throws(ImagePipeline.Error) {
        // See if the server confirmed that the resumable data can be used
        if let resumableData, ResumableData.isResumedResponse(response) {
            data = resumableData.data
            resumedDataCount = Int64(resumableData.data.count)
        }
        resumableData = nil // Get rid of resumable data

        // Check the expected size early to avoid a large `reserveCapacity`
        // allocation when the server reports a content length above the limit.
        let expectedSize = self.expectedSize(of: response)
        if let maximumResponseDataSize = pipeline.configuration.maximumResponseDataSize {
            if expectedSize > 0, expectedSize > maximumResponseDataSize {
                throw .dataDownloadExceededMaximumSize
            }
        }
        if resumedDataCount > 0, expectedSize > 0 {
            data.reserveCapacity(Int(min(expectedSize, maximumReservedCapacity)))
        }
    }

    /// The size of the whole resource: the advertised content length plus the
    /// resumed bytes. Saturates, since Foundation reports a content length it
    /// can't represent as `Int64.max`.
    private func expectedSize(of response: URLResponse) -> Int64 {
        let (size, isOverflow) = response.expectedContentLength.addingReportingOverflow(resumedDataCount)
        return isOverflow ? .max : size
    }

    /// Processes a data chunk. Returns `false` when the size limit is exceeded.
    private func dataTask(didReceiveData chunk: Data, response: URLResponse) throws(ImagePipeline.Error) {
        // Append data and save response
        if data.isEmpty {
            data = chunk
            if response.expectedContentLength > chunk.count {
                data.reserveCapacity(Int(min(response.expectedContentLength, maximumReservedCapacity)))
            }
        } else {
            data.append(chunk)
        }
        urlResponse = response

        if let maximumResponseDataSize = pipeline.configuration.maximumResponseDataSize, data.count > maximumResponseDataSize {
            throw .dataDownloadExceededMaximumSize
        }

        let progress = TaskProgress(completed: Int64(data.count), total: expectedSize(of: response))
        send(progress: progress)

        // If the image hasn't been fully loaded yet, give decoder a chance
        // to decode the data chunk. In case `expectedContentLength` is `0`,
        // progressive decoding doesn't run.
        guard data.count < expectedSize(of: response) else { return }
        send(value: (data, response))
    }

    private func dataTaskDidFinish(error: ImagePipeline.Error? = nil) async {
        guard !isDisposed else { return }

        diagnostics?.endStage(downloadStage) { stage in
            // `URLSession` collected its metrics before the continuation that
            // brought us here resumed, so they say whether the bytes came off
            // the network or out of the session's own cache.
            stage.source = stage.urlSessionMetrics?.isServedFromCache == true ? .httpCache : .network
            stage.bytes = Int64(data.count)
            stage.resumedBytes = resumedDataCount
            if let urlResponse, urlResponse.expectedContentLength >= 0 {
                stage.expectedBytes = expectedSize(of: urlResponse)
            }
        }

        if let error {
            tryToSaveResumableData()
            send(error: error)
            return
        }

        // Sanity check, should never happen in practice
        guard !data.isEmpty else {
            send(error: .dataIsEmpty)
            return
        }

        // Store in data cache
        await storeDataInCacheIfNeeded(data)

        send(value: (data, urlResponse), isCompleted: true)
    }

    // MARK: Async Data Loading

    private func loadAsyncData(_ fetch: @Sendable @escaping () async throws -> Data) {
        downloadStage = diagnostics?.beginStage(.download, queued: true)
        if request.options.contains(.skipDataLoadingQueue) {
            dataLoadTask = Task {
                await self.performAsyncDataLoad(fetch)
            }
            onCancelled = { [weak self] in
                self?.dataLoadTask?.cancel()
            }
        } else {
            operation = pipeline.configuration.dataLoadingQueue.add(priority: priority) { [weak self] in
                await self?.performAsyncDataLoad(fetch)
            }
        }
    }

    private func performAsyncDataLoad(_ fetch: @Sendable @escaping () async throws -> Data) async {
        guard !isDisposed else { return }
        diagnostics?.startStage(downloadStage)
        do {
            let data = try await fetch()
            diagnostics?.endStage(downloadStage) {
                $0.source = .closure
                $0.bytes = Int64(data.count)
            }
            await asyncDataDidFinish(data)
        } catch {
            diagnostics?.endStage(downloadStage) { $0.source = .closure }
            send(error: .dataLoadingFailed(error: error))
        }
    }

    private func asyncDataDidFinish(_ data: Data) async {
        guard !data.isEmpty else {
            send(error: .dataIsEmpty)
            return
        }
        await storeDataInCacheIfNeeded(data)
        send(value: (data, nil), isCompleted: true)
    }

    private func asyncDataDidFail(_ error: Error) {
        send(error: .dataLoadingFailed(error: error))
    }

    private func tryToSaveResumableData() {
        // Try to save resumable data in case the task was cancelled
        // (`URLError.cancelled`) or failed to complete with other error.
        guard pipeline.configuration.isResumableDataEnabled else { return }
        if let response = urlResponse, !data.isEmpty,
           let resumableData = ResumableData(response: response, data: data, resumedDataCount: resumedDataCount) {
            ResumableDataStorage.shared.storeResumableData(resumableData, for: request, pipeline: pipeline)
        } else if let resumableData {
            // The request ended before the server responded – put the data that
            // `performDataLoad` took out of the storage back where it was.
            ResumableDataStorage.shared.storeResumableData(resumableData, for: request, pipeline: pipeline)
        }
    }
}

extension AsyncPipelineTask where Value == (Data, URLResponse?) {
    func storeDataInCacheIfNeeded(_ data: Data) async {
        let request = makeSanitizedRequest()
        guard let dataCache = pipeline.delegate.dataCache(for: request, pipeline: pipeline), shouldStoreDataInDiskCache() else {
            return
        }
        let key = pipeline.cache.makeDataCacheKey(for: request)
        let stage = diagnostics?.beginStage(.diskStore)
        guard let data = await pipeline.willCache(data: data, image: nil, for: request) else {
            diagnostics?.endStage(stage) { $0.cacheKey = diagnosticsDigest(of: key) }
            return
        }
        // Important! Storing directly ignoring `ImageRequest.Options`.
        dataCache.storeData(data, for: key)
        diagnostics?.endStage(stage) {
            $0.cacheKey = diagnosticsDigest(of: key)
            $0.bytes = Int64(data.count)
        }
    }

    /// Returns a request that doesn't contain any information non-related
    /// to data loading.
    private func makeSanitizedRequest() -> ImageRequest {
        var request = request
        request.processors = []
        request.thumbnail = nil
        return request
    }

    private func shouldStoreDataInDiskCache() -> Bool {
        guard containsImageTask(where: { !$0.request.options.contains(.disableDiskCacheWrites) }) else {
            return false
        }
        guard !(request.url?.isLocalResource ?? false) else {
            return false
        }
        switch pipeline.configuration.dataCachePolicy {
        case .automatic:
            return containsImageTask { $0.request.processors.isEmpty }
        case .storeOriginalData:
            return true
        case .storeEncodedImages:
            return false
        case .storeAll:
            return true
        }
    }
}
