// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Wrapper for tasks created by `loadImage` calls.
///
/// Performs all the quick cache lookups and also manages image processing.
/// The coalescing for image processing is implemented on demand (extends the
/// scenarios in which coalescing can kick in).
final class TaskLoadImage: AsyncPipelineTask<ImageResponse>, @unchecked Sendable {
    override func start() {
        if let container = pipeline.cache[request] {
            let response = ImageResponse(container: container, request: request, cacheType: .memory)
            send(value: response, isCompleted: !container.isPreview)
            if !container.isPreview {
                return // The final image is loaded
            }
        }
        if let data = pipeline.cache.cachedData(for: request) {
            decodeCachedData(data)
        } else {
            fetchImage()
        }
    }

    private func decodeCachedData(_ data: Data) {
        let context = ImageDecodingContext(request: request, data: data, cacheType: .disk)
        guard let decoder = pipeline.delegate.imageDecoder(for: context, pipeline: pipeline) else {
            return didFinishDecoding(with: nil)
        }
        decode(context, decoder: decoder) { [weak self] in
            self?.didFinishDecoding(with: try? $0.get())
        }
    }

    private func didFinishDecoding(with response: ImageResponse?) {
        if let response {
            didReceiveImageResponse(response, isCompleted: true)
        } else {
            fetchImage()
        }
    }

    // MARK: Fetch Image

    private func fetchImage() {
        guard !request.options.contains(.returnCacheDataDontLoad) else {
            return send(error: .dataMissingInCache)
        }
        if let processor = request.processors.last {
            let request = request.withProcessors(request.processors.dropLast())
            dependency = pipeline.makeTaskLoadImage(for: request).subscribe(self) { [weak self] in
                self?.process($0, isCompleted: $1, processor: processor)
            }
        } else {
            dependency = pipeline.makeTaskFetchOriginalImage(for: request).subscribe(self) { [weak self] in
                self?.didReceiveImageResponse($0, isCompleted: $1)
            }
        }
    }

    // MARK: Processing

    private func process(_ response: ImageResponse, isCompleted: Bool, processor: any ImageProcessing) {
        guard !isDisposed else { return }
        if isCompleted {
            operation?.cancel() // Cancel any potential pending progressive
        } else if operation != nil {
            return // Back pressure - already processing another progressive image
        }
        let context = ImageProcessingContext(request: request, response: response, isCompleted: isCompleted)
        operation = pipeline.configuration.imageProcessingQueue.add { [weak self] in
            guard let self else { return }
            let result = signpost(isCompleted ? "ProcessImage" : "ProcessProgressiveImage") {
                Result {
                    var response = response
                    response.container = try processor.process(response.container, context: context)
                    return response
                }.mapError { error in
                    ImagePipeline.Error.processingFailed(processor: processor, context: context, error: error)
                }
            }
            self.pipeline.queue.async {
                self.operation = nil
                self.didFinishProcessing(result: result, isCompleted: isCompleted)
            }
        }
    }

    private func didFinishProcessing(result: Result<ImageResponse, ImagePipeline.Error>, isCompleted: Bool) {
        switch result {
        case .success(let response):
            didReceiveImageResponse(response, isCompleted: isCompleted)
        case .failure(let error):
            if isCompleted {
                send(error: error)
            }
        }
    }

    // MARK: Decompression

    private func didReceiveImageResponse(_ response: ImageResponse, isCompleted: Bool) {
        guard isDecompressionNeeded(for: response) else {
            return didReceiveDecompressedImage(response, isCompleted: isCompleted)
        }
        guard !isDisposed else { return }
        if isCompleted {
            operation?.cancel() // Cancel any potential pending progressive decompression tasks
        } else if operation != nil {
            return  // Back-pressure: receiving progressive scans too fast
        }
        operation = pipeline.configuration.imageDecompressingQueue.add { [weak self] in
            guard let self else { return }
            let response = signpost(isCompleted ? "DecompressImage" : "DecompressProgressiveImage") {
                self.pipeline.delegate.decompress(response: response, request: self.request, pipeline: self.pipeline)
            }
            self.pipeline.queue.async {
                self.operation = nil
                self.didReceiveDecompressedImage(response, isCompleted: isCompleted)
            }
        }
    }

    private func isDecompressionNeeded(for response: ImageResponse) -> Bool {
        ImageDecompression.isDecompressionNeeded(for: response) &&
        !request.options.contains(.skipDecompression) &&
        hasDirectSubscribers &&
        pipeline.delegate.shouldDecompress(response: response, for: request, pipeline: pipeline)
    }

    private func didReceiveDecompressedImage(_ response: ImageResponse, isCompleted: Bool) {
        storeImageInCaches(response)
        send(value: response, isCompleted: isCompleted)
    }

    // MARK: Caching

    private func storeImageInCaches(_ response: ImageResponse) {
        guard hasDirectSubscribers else {
            return
        }
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
        pipeline.configuration.imageEncodingQueue.addOperation { [weak pipeline, request] in
            guard let pipeline else { return }
            let encodedData = signpost("EncodeImage") {
                encoder.encode(response.container, context: context)
            }
            guard let data = encodedData, !data.isEmpty else { return }
            pipeline.delegate.willCache(data: data, image: response.container, for: request, pipeline: pipeline) {
                guard let data = $0, !data.isEmpty else { return }
                // Important! Storing directly ignoring `ImageRequest.Options`.
                dataCache.storeData(data, for: key) // This is instant, writes are async
            }
        }
        if pipeline.configuration.debugIsSyncImageEncoding { // Only for debug
            pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()
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

    /// Returns `true` if the task has at least one image task that was directly
    /// subscribed to it, which means that the request was initiated by the
    /// user and not the framework.
    private var hasDirectSubscribers: Bool {
        subscribers.contains { $0 is ImageTask }
    }
}
