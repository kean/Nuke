// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Fetches original image from the data loader (`DataLoading`) and stores it
/// in the disk cache (`DataCaching`).
final class TaskFetchOriginalData: AsyncPipelineTask<(Data, URLResponse?)>, @unchecked Sendable {
    private var urlResponse: URLResponse?
    private var resumableData: ResumableData?
    private var resumedDataCount: Int64 = 0
    private var data = Data()

    override func start() {
        if let fetch = request.dataFetchClosure {
            loadAsyncData(fetch)
            return
        }

        guard let urlRequest = request.urlRequest, let url = urlRequest.url else {
            // A malformed URL prevented a URL request from being initiated.
            send(error: .dataLoadingFailed(error: URLError(.badURL)))
            return
        }

        if url.isLocalResource && pipeline.configuration.isLocalResourcesSupportEnabled {
            do {
                let data = try Data(contentsOf: url)
                send(value: (data, nil), isCompleted: true)
            } catch {
                send(error: .dataLoadingFailed(error: error))
            }
            return
        }

        if let rateLimiter = pipeline.rateLimiter {
            // Rate limiter is synchronized on pipeline's queue. Delayed work is
            // executed asynchronously also on the same queue.
            rateLimiter.execute { [weak self] in
                guard let self, !self.isDisposed else {
                    return false
                }
                self.loadData(urlRequest: urlRequest)
                return true
            }
        } else { // Start loading immediately.
            loadData(urlRequest: urlRequest)
        }
    }

    private func loadData(urlRequest: URLRequest) {
        if request.options.contains(.skipDataLoadingQueue) {
            Task { @ImagePipelineActor in
                await self.performDataLoad(urlRequest: urlRequest)
            }
        } else {
            // Wrap data request in an operation to limit the maximum number of
            // concurrent data tasks.
            operation = pipeline.configuration.dataLoadingQueue.add { [weak self] in
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

        signpost(self, "LoadImageData", .begin, "URL: \(urlRequest.url?.absoluteString ?? ""), resumable data: \(Formatter.bytes(resumableData?.data.count ?? 0))")

        onCancelled = { [weak self] in
            guard let self else { return }
            signpost(self, "LoadImageData", .end, "Cancelled")
            self.tryToSaveResumableData()
        }

        let dataLoader = pipeline.delegate.dataLoader(for: request, pipeline: pipeline)

        do {
            urlRequest = try await pipeline.delegate.willLoadData(for: request, urlRequest: urlRequest, pipeline: pipeline)
            let (stream, response) = try await dataLoader.loadData(with: urlRequest)

            guard !isDisposed else { return }

            try dataTask(didReceiveResponse: response)

            for try await chunk in stream {
                guard !isDisposed else { return }
                try dataTask(didReceiveData: chunk, response: response)
            }

            signpost(self, "LoadImageData", .end, "Finished with size \(Formatter.bytes(self.data.count))")
            dataTaskDidFinish()
        } catch {
            signpost(self, "LoadImageData", .end, "Failed")
            if let error = error as? ImagePipeline.Error {
                dataTaskDidFinish(error: error)
            } else {
                dataTaskDidFinish(error: .dataLoadingFailed(error: error))
            }
        }
    }

    /// Processes the initial response. Returns `false` if the size limit is
    /// exceeded early (based on expected content length).
    private func dataTask(didReceiveResponse response: URLResponse) throws(ImagePipeline.Error) {
        // See if the server confirmed that the resumable data can be used
        if let resumableData, ResumableData.isResumedResponse(response) {
            data = resumableData.data
            resumedDataCount = Int64(resumableData.data.count)
            let expectedSize = response.expectedContentLength + resumedDataCount
            if expectedSize > 0, expectedSize <= Int.max {
                data.reserveCapacity(Int(expectedSize))
            }
            signpost(self, "LoadImageData", .event, "Resumed with data \(Formatter.bytes(resumedDataCount))")
        }
        resumableData = nil // Get rid of resumable data

        // Check the expected size early to avoid a large `reserveCapacity`
        // allocation when the server reports a content length above the limit.
        if let maximumResponseDataSize = pipeline.configuration.maximumResponseDataSize {
            let expectedSize = response.expectedContentLength + resumedDataCount
            if expectedSize > 0, expectedSize > maximumResponseDataSize {
                throw .dataDownloadExceededMaximumSize
            }
        }
    }

    /// Processes a data chunk. Returns `false` when the size limit is exceeded.
    private func dataTask(didReceiveData chunk: Data, response: URLResponse) throws(ImagePipeline.Error) {
        // Append data and save response
        if data.isEmpty {
            data = chunk
            if response.expectedContentLength > chunk.count, response.expectedContentLength <= Int.max {
                data.reserveCapacity(Int(response.expectedContentLength))
            }
        } else {
            data.append(chunk)
        }
        urlResponse = response

        if let maximumResponseDataSize = pipeline.configuration.maximumResponseDataSize, data.count > maximumResponseDataSize {
            throw .dataDownloadExceededMaximumSize
        }

        let progress = TaskProgress(completed: Int64(data.count), total: response.expectedContentLength + resumedDataCount)
        send(progress: progress)

        // If the image hasn't been fully loaded yet, give decoder a chance
        // to decode the data chunk. In case `expectedContentLength` is `0`,
        // progressive decoding doesn't run.
        guard data.count < response.expectedContentLength else { return }
        send(value: (data, response))
    }

    private func dataTaskDidFinish(error: ImagePipeline.Error? = nil) {
        guard !isDisposed else { return }

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
        storeDataInCacheIfNeeded(data)

        send(value: (data, urlResponse), isCompleted: true)
    }

    // MARK: Async Data Loading

    private func loadAsyncData(_ fetch: @Sendable @escaping () async throws -> Data) {
        if request.options.contains(.skipDataLoadingQueue) {
            Task { await self.performAsyncDataLoad(fetch) }
        } else {
            operation = pipeline.configuration.dataLoadingQueue.add { [weak self] in
                await self?.performAsyncDataLoad(fetch)
            }
        }
    }

    private func performAsyncDataLoad(_ fetch: @Sendable @escaping () async throws -> Data) async {
        guard !isDisposed else { return }
        do {
            let data = try await fetch()
            asyncDataDidFinish(data)
        } catch {
            send(error: .dataLoadingFailed(error: error))
        }
    }

    private func asyncDataDidFinish(_ data: Data) {
        guard !data.isEmpty else {
            send(error: .dataIsEmpty)
            return
        }
        storeDataInCacheIfNeeded(data)
        send(value: (data, nil), isCompleted: true)
    }

    private func asyncDataDidFail(_ error: Error) {
        send(error: .dataLoadingFailed(error: error))
    }

    private func tryToSaveResumableData() {
        // Try to save resumable data in case the task was cancelled
        // (`URLError.cancelled`) or failed to complete with other error.
        if pipeline.configuration.isResumableDataEnabled,
           let response = urlResponse, !data.isEmpty,
           let resumableData = ResumableData(response: response, data: data) {
            ResumableDataStorage.shared.storeResumableData(resumableData, for: request, pipeline: pipeline)
        }
    }
}

extension AsyncPipelineTask where Value == (Data, URLResponse?) {
    func storeDataInCacheIfNeeded(_ data: Data) {
        let request = makeSanitizedRequest()
        guard let dataCache = pipeline.delegate.dataCache(for: request, pipeline: pipeline), shouldStoreDataInDiskCache() else {
            return
        }
        let key = pipeline.cache.makeDataCacheKey(for: request)
        pipeline.delegate.willCache(data: data, image: nil, for: request, pipeline: pipeline) {
            guard let data = $0 else { return }
            // Important! Storing directly ignoring `ImageRequest.Options`.
            dataCache.storeData(data, for: key)
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
        let imageTasks = imageTasks
        guard imageTasks.contains(where: { !$0.request.options.contains(.disableDiskCacheWrites) }) else {
            return false
        }
        guard !(request.url?.isLocalResource ?? false) else {
            return false
        }
        switch pipeline.configuration.dataCachePolicy {
        case .automatic:
            return imageTasks.contains { $0.request.processors.isEmpty }
        case .storeOriginalData:
            return true
        case .storeEncodedImages:
            return false
        case .storeAll:
            return true
        }
    }
}
