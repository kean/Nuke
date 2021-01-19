// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

/// Dependencies for `ImageDataTask`.
final class OriginalDataTaskContext {
    let configuration: ImagePipeline.Configuration
    let queue: DispatchQueue
    let rateLimiter: RateLimiter?
    let log: OSLog

    init(configuration: ImagePipeline.Configuration, queue: DispatchQueue, log: OSLog) {
        self.configuration = configuration
        self.queue = queue
        self.rateLimiter = configuration.isRateLimiterEnabled ? RateLimiter(queue: queue) : nil
        self.log = log
    }
}

final class OriginalDataTask: Task<(Data, URLResponse?), ImagePipeline.Error> {
    private let service: OriginalDataTaskContext
    // TODO: temp
    private var configuration: ImagePipeline.Configuration { service.configuration }
    private var queue: DispatchQueue { service.queue }
    private let request: ImageRequest
    private var urlResponse: URLResponse?
    private var resumableData: ResumableData?
    private var resumedDataCount: Int64 = 0
    private lazy var data = Data()

    init(service: OriginalDataTaskContext, request: ImageRequest) {
        self.service = service
        self.request = request
    }

    override func start() {
        if let rateLimiter = service.rateLimiter {
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
        guard let cache = configuration.dataCache, configuration.dataCacheOptions.storedItems.contains(.originalImageData), request.cachePolicy != .reloadIgnoringCachedData else {
            loadImageData() // Skip disk cache lookup, load data
            return
        }

        let key = request.makeCacheKeyForOriginalImageData()
        let operation = BlockOperation { [weak self] in
            guard let self = self else { return }

            let log = Log(self.service.log, "Read Cached Image Data")
            log.signpost(.begin)
            let data = cache.cachedData(for: key)
            log.signpost(.end)

            self.queue.async {
                if let data = data {
                    self.send(value: (data, nil), isCompleted: true)
                } else {
                    self.loadImageData()
                }
            }
        }
        self.operation = operation
        configuration.dataCachingQueue.addOperation(operation)
    }

    private func loadImageData() {
        // Wrap data request in an operation to limit maximum number of
        // concurrent data tasks.
        let operation = Operation(starter: { [weak self] finish in
            guard let self = self else {
                return finish()
            }
            self.queue.async {
                self.loadImageData(finish: finish)
            }
        })
        configuration.dataLoadingQueue.addOperation(operation)
        self.operation = operation
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

        let log = Log(service.log, "Load Image Data")
        log.signpost(.begin, "URL: \(urlRequest.url?.absoluteString ?? ""), resumable data: \(Log.bytes(resumableData?.data.count ?? 0))")

        let dataTask = configuration.dataLoader.loadData(
            with: urlRequest,
            didReceiveData: { [weak self] data, response in
                guard let self = self else { return }
                self.queue.async {
                    self.imageDataLoadingTask(didReceiveData: data, response: response, log: log)
                }
            },
            completion: { [weak self] error in
                finish() // Finish the operation!
                guard let self = self else { return }
                self.queue.async {
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

    func imageDataLoadingTaskDidFinish(error: Swift.Error?) {
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

    func tryToSaveResumableData() {
        // Try to save resumable data in case the task was cancelled
        // (`URLError.cancelled`) or failed to complete with other error.
        if configuration.isResumableDataEnabled,
           let response = urlResponse, !data.isEmpty,
           let resumableData = ResumableData(response: response, data: data) {
            ResumableData.storeResumableData(resumableData, for: request.urlRequest)
        }
    }
}
