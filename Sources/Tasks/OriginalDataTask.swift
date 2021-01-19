// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Fetches original image data from data cache (`DataCaching`) or data loader
/// (`DataLoading`) in case data is not available in cache.
final class OriginalDataTask: ImagePipelineTask<(Data, URLResponse?)> {
    private var urlResponse: URLResponse?
    private var resumableData: ResumableData?
    private var resumedDataCount: Int64 = 0
    private lazy var data = Data()

    override func start() {
        if let rateLimiter = pipeline.rateLimiter {
            // Rate limiter is synchronized on pipeline's queue. Delayed work is
            // executed asynchronously also on this same queue.
            rateLimiter.execute { [weak self] in
                guard let self = self, !self.isDisposed else {
                    return false
                }
                self.actuallyStart()
                return true
            }
        } else { // Start loading immediately.
            actuallyStart()
        }
    }

    private func actuallyStart() {
        guard let dataCache = configuration.dataCache, configuration.dataCacheOptions.storedItems.contains(.originalImageData), request.cachePolicy != .reloadIgnoringCachedData else {
            loadImageData() // Skip disk cache lookup, load data
            return
        }
        operation = configuration.dataCachingQueue.add { [weak self] in
            self?.getCachedData(dataCache: dataCache)
        }
    }

    private func getCachedData(dataCache: DataCaching) {
        let key = request.makeCacheKeyForOriginalImageData()
        let data = pipeline.signpost("Read Cached Image Data") {
            dataCache.cachedData(for: key)
        }
        pipeline.async {
            if let data = data {
                self.send(value: (data, nil), isCompleted: true)
            } else {
                self.loadImageData()
            }
        }
    }

    private func loadImageData() {
        // Wrap data request in an operation to limit maximum number of
        // concurrent data tasks.
        operation = configuration.dataLoadingQueue.add { [weak self] finish in
            guard let self = self else {
                return finish()
            }
            self.pipeline.async {
                self.loadImageData(finish: finish)
            }
        }
    }

    // This methods gets called inside data loading operation (Operation).
    private func loadImageData(finish: @escaping () -> Void) {
        guard !isDisposed else {
            return finish() // Task was cancelled by the time it got a chance to start
        }

        var urlRequest = request.urlRequest

        // Read and remove resumable data from cache (we're going to insert it
        // back in the cache if the request fails to complete again).
        if configuration.isResumableDataEnabled,
           let resumableData = ResumableData.removeResumableData(for: urlRequest) {
            // Update headers to add "Range" and "If-Range" headers
            resumableData.resume(request: &urlRequest)
            // Save resumable data to be used later (before using it, the pipeline
            // verifies that the server returns "206 Partial Content")
            self.resumableData = resumableData
        }

        let log = pipeline.log("Load Image Data")
        log.signpost(.begin, "URL: \(urlRequest.url?.absoluteString ?? ""), resumable data: \(Log.bytes(resumableData?.data.count ?? 0))")

        let dataTask = configuration.dataLoader.loadData(
            with: urlRequest,
            didReceiveData: { [weak self] data, response in
                guard let self = self else { return }
                self.pipeline.async {
                    self.imageDataLoadingTask(didReceiveData: data, response: response, log: log)
                }
            },
            completion: { [weak self] error in
                finish() // Finish the operation!
                guard let self = self else { return }
                self.pipeline.async {
                    log.signpost(.end, "Finished with size \(Log.bytes(self.data.count))")
                    self.imageDataLoadingTaskDidFinish(error: error)
                }
            })

        onCancelled = { [weak self] in
            guard let self = self else { return }

            log.signpost(.end, "Cancelled")
            dataTask.cancel()
            finish() // Finish the operation!

            self.tryToSaveResumableData()
        }
    }

    private func imageDataLoadingTask(didReceiveData chunk: Data, response: URLResponse, log: Log) {
        // Check if this is the first response.
        if urlResponse == nil {
            // See if the server confirmed that the resumable data can be used
            if let resumableData = resumableData, ResumableData.isResumedResponse(response) {
                data = resumableData.data
                resumedDataCount = Int64(resumableData.data.count)
                log.signpost(.event, "Resumed with data \(Log.bytes(resumedDataCount))")
            }
            resumableData = nil // Get rid of resumable data
        }

        // Append data and save response
        data.append(chunk)
        urlResponse = response

        let progress = TaskProgress(completed: Int64(data.count), total: response.expectedContentLength + resumedDataCount)
        send(progress: progress)

        // If the image hasn't been fully loaded yet, give decoder a change
        // to decode the data chunk. In case `expectedContentLength` is `0`,
        // progressive decoding doesn't run.
        guard data.count < response.expectedContentLength else { return }

        send(value: (data, response))
    }

    private func imageDataLoadingTaskDidFinish(error: Swift.Error?) {
        if let error = error {
            tryToSaveResumableData()
            send(error: .dataLoadingFailed(error))
            return
        }

        // Sanity check, should never happen in practice
        guard !data.isEmpty else {
            send(error: .dataLoadingFailed(URLError(.unknown, userInfo: [:])))
            return
        }

        // Store in data cache
        if let dataCache = configuration.dataCache, configuration.dataCacheOptions.storedItems.contains(.originalImageData) {
            let key = request.makeCacheKeyForOriginalImageData()
            dataCache.storeData(data, for: key)
        }

        send(value: (data, urlResponse), isCompleted: true)
    }

    private func tryToSaveResumableData() {
        // Try to save resumable data in case the task was cancelled
        // (`URLError.cancelled`) or failed to complete with other error.
        if configuration.isResumableDataEnabled,
           let response = urlResponse, !data.isEmpty,
           let resumableData = ResumableData(response: response, data: data) {
            ResumableData.storeResumableData(resumableData, for: request.urlRequest)
        }
    }
}
