// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Fetches original image from the data loader (`DataLoading`) and stores it
/// in the disk cache (`DataCaching`).
final class JobFetchData: AsyncPipelineTask<(Data, URLResponse?)> {
    private var urlResponse: URLResponse?
    private var resumableData: ResumableData?
    private var resumedDataCount: Int64 = 0
    private var data = Data()
    private var task: Task<Void, Never>?

    override func start() {
        if let rateLimiter = pipeline.rateLimiter {
            // Rate limiter is synchronized on pipeline's queue. Delayed work is
            // executed asynchronously also on the same queue.
            rateLimiter.execute { [weak self] in
                guard let self, !self.isDisposed else {
                    return false
                }
                self.actuallyStart()
                return true
            }
        } else { // Start loading immediately.
            actuallyStart()
        }
    }

    override func onCancel() {
        task?.cancel()
        super.onCancel() // Important
    }

    private func actuallyStart() {
        switch request.resource {
        case .url(let url):
            guard let url else {
                return send(error: .dataLoadingFailed(error: URLError(.badURL)))
            }
            start(with: URLRequest(url: url))
        case .urlRequest(let urlRequest):
            start(with: urlRequest)
        case .closure(let closure, _):
            task = Task { @ImagePipelineActor in
                await self.loadData(with: closure)
            }
        }
    }

    // MARK: URLRequest

    private func start(with urlRequest: URLRequest) {
        if pipeline.configuration.isLocalResourcesSupportEnabled, let url = urlRequest.url, url.isLocalResource {
            do {
                let data = try Data(contentsOf: url)
                send(value: (data, nil), isCompleted: true)
            } catch {
                send(error: .dataLoadingFailed(error: error))
            }
            return
        }
        task = Task { @ImagePipelineActor in
            await self.actuallyLoadData(urlRequest: urlRequest)
        }
    }

    // This methods gets called inside data loading operation (Operation).
    private func actuallyLoadData(urlRequest: URLRequest) async {
        guard !isDisposed else { return }

        // Read and remove resumable data from cache (we're going to insert it
        // back in the cache if the request fails to complete again).
        var urlRequest = urlRequest
        if pipeline.configuration.isResumableDataEnabled,
           let resumableData = ResumableDataStorage.shared.removeResumableData(for: request, namespace: pipeline.id) {
            // Update headers to add "Range" and "If-Range" headers
            resumableData.resume(request: &urlRequest)
            // Save resumable data to be used later (before using it, the pipeline
            // verifies that the server returns "206 Partial Content")
            self.resumableData = resumableData
        }

        signpost(self, "LoadImageData", .begin, "URL: \(String(describing: urlRequest.url))")

        let dataLoader = pipeline.delegate.dataLoader(for: request, pipeline: pipeline)

        do {
            for try await (data, response) in dataLoader.loadData(for: urlRequest) {
                dataTask(didReceiveData: data, response: response)
            }
            dataTaskDidFinish(error: nil)
        } catch {
            dataTaskDidFinish(error: error)
        }
        signpost(self, "LoadImageData", .end, "Finished with size \(Formatter.bytes(self.data.count))")
    }

    private func dataTask(didReceiveData chunk: Data, response: URLResponse) {
        // Check if this is the first response.
        if urlResponse == nil {
            // See if the server confirmed that the resumable data can be used
            if let resumableData, ResumableData.isResumedResponse(response) {
                data = resumableData.data
                resumedDataCount = Int64(resumableData.data.count)
                signpost(self, "LoadImageData", .event, "Resumed with data \(Formatter.bytes(resumedDataCount))")
            }
            resumableData = nil // Get rid of resumable data
        }

        // Append data and save response
        if data.isEmpty {
            data = chunk
        } else {
            data.append(chunk)
        }
        urlResponse = response

        let progress = JobProgress(completed: Int64(data.count), total: response.expectedContentLength + resumedDataCount)
        send(progress: progress)

        // If the image hasn't been fully loaded yet, give decoder a change
        // to decode the data chunk. In case `expectedContentLength` is `0`,
        // progressive decoding doesn't run.
        guard data.count < response.expectedContentLength else { return }

        send(value: (data, response))
    }

    private func dataTaskDidFinish(error: Swift.Error?) {
        if let error {
            tryToSaveResumableData()
            send(error: .dataLoadingFailed(error: error))
            return
        }

        // Sanity check, should never happen in practice
        guard !data.isEmpty else {
            send(error: .dataIsEmpty)
            return
        }

        storeDataInCacheIfNeeded(data)

        send(value: (data, urlResponse), isCompleted: true)
    }

    private func tryToSaveResumableData() {
        // Try to save resumable data in case the task was cancelled
        // (`URLError.cancelled`) or failed to complete with other error.
        if pipeline.configuration.isResumableDataEnabled,
           let response = urlResponse, !data.isEmpty,
           let resumableData = ResumableData(response: response, data: data) {
            ResumableDataStorage.shared.storeResumableData(resumableData, for: request, namespace: pipeline.id)
        }
    }

    // MARK: Closure

    private func loadData(with closure: (@Sendable @escaping () async throws -> Data)) async {
        guard !isDisposed else {
            return
        }
        guard let closure = request.closure else {
            send(error: .dataLoadingFailed(error: URLError(.unknown))) // This is just a placeholder error, never thrown
            return assertionFailure("This should never happen")
        }
        do {
            let data = try await closure()
            guard !data.isEmpty else {
                throw ImageTask.Error.dataIsEmpty
            }
            send(value: (data, nil), isCompleted: true)
        } catch {
            send(error: .dataLoadingFailed(error: error))
        }
    }

    // MARK: - DataCaching

    private func storeDataInCacheIfNeeded(_ data: Data) {
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
        request.userInfo[.thumbnailKey] = nil
        return request
    }

    private func shouldStoreDataInDiskCache() -> Bool {
        let tasks = tasks
        guard tasks.contains(where: { !$0.request.options.contains(.disableDiskCacheWrites) }) else {
            return false
        }
        guard !(request.url?.isLocalResource ?? false) else {
            return false
        }
        switch pipeline.configuration.dataCachePolicy {
        case .automatic:
            return tasks.contains { $0.request.processors.isEmpty }
        case .storeOriginalData:
            return true
        case .storeEncodedImages:
            return false
        case .storeAll:
            return true
        }
    }
}
