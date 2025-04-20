// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

// Each task holds a strong reference to the pipeline. This is by design. The
// user does not need to hold a strong reference to the pipeline.
class AsyncPipelineTask<Value: Sendable>: Job<Value> {
    let pipeline: ImagePipeline
    // A canonical request representing the unit work performed by the task.
    let request: ImageRequest

    init(_ pipeline: ImagePipeline, _ request: ImageRequest) {
        self.pipeline = pipeline
        self.request = request
    }
}

// MARK: - AsyncPipelineTask (Data Caching)

extension AsyncPipelineTask {
    func storeImageInCaches(_ response: ImageResponse) {
        pipeline.cache[request] = response.container
        if shouldStoreResponseInDataCache(response) {
            storeImageInDataCache(response)
        }
    }

    private func storeImageInDataCache(_ response: ImageResponse) {
        guard let dataCache = pipeline.delegate.dataCache(for: request, pipeline: pipeline) else {
            return
        }
        let context = ImageEncodingContext(request: request, image: response.image, urlResponse: response.urlResponse)
        let encoder = pipeline.delegate.imageEncoder(for: context, pipeline: pipeline)
        let key = pipeline.cache.makeDataCacheKey(for: request)

        guard !pipeline.configuration.debugIsSyncImageEncoding else {
            // TODO: remove some of this duplication
            if let data = encoder.encode(response.container, context: context), !data.isEmpty {
                pipeline.delegate.willCache(data: data, image: response.container, for: request, pipeline: pipeline) {
                    guard let data = $0, !data.isEmpty else { return }
                    dataCache.storeData(data, for: key)
                }
            }
            return
        }

        pipeline.configuration.imageEncodingQueue.add(priority: priority) { [weak pipeline, request] in
            guard let pipeline else { return }
            let encodedData = await performInBackground {
                signpost("EncodeImage") {
                    encoder.encode(response.container, context: context)
                }
            }
            guard let data = encodedData, !data.isEmpty else { return }
            pipeline.delegate.willCache(data: data, image: response.container, for: request, pipeline: pipeline) {
                guard let data = $0, !data.isEmpty else { return }
                // Important! Storing directly ignoring `ImageRequest.Options`.
                dataCache.storeData(data, for: key) // This is instant, writes are async
            }
        }
    }

    private func shouldStoreResponseInDataCache(_ response: ImageResponse) -> Bool {
        guard !response.container.isPreview,
              !(response.cacheType == .disk),
              !(request.url?.isLocalResource ?? false) else {
            return false
        }
        let isProcessed = !request.processors.isEmpty || request.thumbnail != nil
        switch pipeline.configuration.dataCachePolicy {
        case .automatic:
            return isProcessed
        case .storeOriginalData:
            return false
        case .storeEncodedImages:
            return true
        case .storeAll:
            return isProcessed
        }
    }
}

// MARK: - AsyncPipelineTask (Data Caching)

extension AsyncPipelineTask {
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
        guard !request.options.contains(.disableDiskCacheWrites) else {
            return false
        }
        guard !(request.url?.isLocalResource ?? false) else {
            return false
        }
        switch pipeline.configuration.dataCachePolicy {
        case .automatic:
            return request.processors.isEmpty
        case .storeOriginalData:
            return true
        case .storeEncodedImages:
            return false
        case .storeAll:
            return true
        }
    }
}
