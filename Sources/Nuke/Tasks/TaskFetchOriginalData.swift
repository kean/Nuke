// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Fetches original image from the data loader (`DataLoading`) and stores it
/// in the disk cache (`DataCaching`).
final class TaskFetchOriginalData: AsyncPipelineTask<(Data, URLResponse?)> {
    private var urlResponse: URLResponse?
    private var resumableData: ResumableData?
    private var resumedDataCount: Int64 = 0
    private var data = Data()

    override func start() {
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
            loadData(urlRequest: urlRequest, finish: { /* do nothing */ })
        } else {
            // Wrap data request in an operation to limit the maximum number of
            // concurrent data tasks.
            operation = pipeline.configuration.dataLoadingQueue.add { [weak self] finish in
                guard let self else {
                    return finish()
                }
                self.pipeline.queue.async {
                    self.loadData(urlRequest: urlRequest, finish: finish)
                }
            }
        }
    }

    // This methods gets called inside data loading operation (Operation).
    private func loadData(urlRequest: URLRequest, finish: @escaping () -> Void) {
        guard !isDisposed else {
            return finish()
        }
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

        let dataLoader = pipeline.delegate.dataLoader(for: request, pipeline: pipeline)
        let dataTask = dataLoader.loadData(with: urlRequest, didReceiveData: { [weak self] data, response in
            guard let self else { return }
            self.pipeline.queue.async {
                self.dataTask(didReceiveData: data, response: response)
            }
        }, completion: { [weak self] error in
            finish() // Finish the operation!
            guard let self else { return }
            signpost(self, "LoadImageData", .end, "Finished with size \(Formatter.bytes(self.data.count))")
            self.pipeline.queue.async {
                self.dataTaskDidFinish(error: error)
            }
        })

        onCancelled = { [weak self] in
            guard let self else { return }

            signpost(self, "LoadImageData", .end, "Cancelled")
            dataTask.cancel()
            finish() // Finish the operation!

            self.tryToSaveResumableData()
        }
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

        let progress = TaskProgress(completed: Int64(data.count), total: response.expectedContentLength + resumedDataCount)
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

        // Store in data cache
        storeDataInCacheIfNeeded(data)

        send(value: (data, urlResponse), isCompleted: true)
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
        request.userInfo[.thumbnailKey] = nil
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
