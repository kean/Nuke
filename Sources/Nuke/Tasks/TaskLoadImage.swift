// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Wrapper for tasks created by `loadImage` calls.
///
/// Performs all the quick cache lookups and also manages image processing.
/// The coalescing for image processing is implemented on demand (extends the
/// scenarios in which coalescing can kick in).
final class TaskLoadImage: ImagePipelineTask<ImageResponse> {
    override func start() {
        // Memory cache lookup
        if let image = pipeline.cache[request] {
            let response = ImageResponse(container: image, request: request, cacheType: .memory)
            send(value: response, isCompleted: !image.isPreview)
            if !image.isPreview {
                return // Already got the result!
            }
        }

        // Disk cache lookup
        if let dataCache = pipeline.delegate.dataCache(for: request, pipeline: pipeline),
           !request.options.contains(.disableDiskCacheReads) {
            operation = pipeline.configuration.dataCachingQueue.add { [weak self] in
                self?.getCachedData(dataCache: dataCache)
            }
            return
        }

        // Fetch image
        fetchImage()
    }

    // MARK: Disk Cache Lookup

    private func getCachedData(dataCache: any DataCaching) {
        let data = signpost("ReadCachedProcessedImageData") {
            pipeline.cache.cachedData(for: request)
        }
        pipeline.queue.async {
            if let data {
                self.didReceiveCachedData(data)
            } else {
                self.fetchImage()
            }
        }
    }

    private func didReceiveCachedData(_ data: Data) {
        guard !isDisposed else { return }

        let context = ImageDecodingContext(request: request, data: data, isCompleted: true, urlResponse: nil, cacheType: .disk)
        guard let decoder = pipeline.delegate.imageDecoder(for: context, pipeline: pipeline) else {
            // This shouldn't happen in practice unless encoder/decoder pair
            // for data cache is misconfigured.
            return fetchImage()
        }

        @Sendable func decode() -> ImageResponse? {
            signpost("DecodeCachedProcessedImageData") {
                try? decoder.decode(context)
            }
        }
        if !decoder.isAsynchronous {
            didDecodeCachedData(decode())
        } else {
            operation = pipeline.configuration.imageDecodingQueue.add { [weak self] in
                guard let self else { return }
                let response = decode()
                self.pipeline.queue.async {
                    self.didDecodeCachedData(response)
                }
            }
        }
    }

    private func didDecodeCachedData(_ response: ImageResponse?) {
        if let response {
            decompressImageIfNeeded(response, isCompleted: true, isFromDiskCache: true)
        } else {
            fetchImage()
        }
    }

    // MARK: Fetch Image

    private func fetchImage() {
        guard !request.options.contains(.returnCacheDataDontLoad) else {
            return send(error: .dataMissingInCache)
        }

        let processors = request.processors
        if let processor = processors.last {
            let request = request.withProcessors(processors.dropLast())
            dependency = pipeline.makeTaskLoadImage(for: request).subscribe(self) { [weak self] in
                self?.process($0, isCompleted: $1, processor: processor)
            }
        } else {
            dependency = pipeline.makeTaskFetchDecodedImage(for: request).subscribe(self) { [weak self] in
                self?.decompressImageIfNeeded($0, isCompleted: $1)
            }
        }
    }

    // MARK: Processing

    /// - parameter processors: Remaining processors to by applied
    private func process(_ response: ImageResponse, isCompleted: Bool, processor: any ImageProcessing) {
        if isCompleted {
            operation?.cancel() // Cancel any potential pending progressive
        } else if operation != nil {
            return // Back pressure - already processing another progressive image
        }

        let context = ImageProcessingContext(request: request, response: response, isCompleted: isCompleted)

        @Sendable func process() -> Result<ImageResponse, Error> {
            signpost("ProcessImage", isCompleted ? "FinalImage" : "ProgressiveImage") {
                Result(catching: {
                    var response = response
                    response.container = try processor.process(response.container, context: context)
                    return response
                })
            }
        }

        operation = pipeline.configuration.imageProcessingQueue.add { [weak self] in
            guard let self else { return }
            let result = process()
            self.pipeline.queue.async {
                self.didFinishProcessing(result: result, processor: processor, context: context)
            }
        }
    }

    private func didFinishProcessing(result: Result<ImageResponse, Error>, processor: any ImageProcessing, context: ImageProcessingContext) {
        operation = nil

        switch result {
        case .success(let response):
            storeImageInCaches(response, isFromDiskCache: false)
            send(value: response, isCompleted: context.isCompleted)
        case .failure(let error):
            if context.isCompleted {
                self.send(error: .processingFailed(processor: processor, context: context, error: error))
            }
        }
    }

    // MARK: Decompression

    private func decompressImageIfNeeded(_ response: ImageResponse, isCompleted: Bool, isFromDiskCache: Bool = false) {
        guard isDecompressionNeeded(for: response) else {
            storeImageInCaches(response, isFromDiskCache: isFromDiskCache)
            send(value: response, isCompleted: isCompleted)
            return
        }

        if isCompleted {
            operation?.cancel() // Cancel any potential pending progressive decompression tasks
        } else if operation != nil {
            return  // Back-pressure: we are receiving data too fast
        }

        guard !isDisposed else { return }

        operation = pipeline.configuration.imageDecompressingQueue.add { [weak self] in
            guard let self else { return }

            let response = signpost("DecompressImage", isCompleted ? "FinalImage" : "ProgressiveImage") {
                self.pipeline.delegate.decompress(response: response, request: self.request, pipeline: self.pipeline)
            }

            self.pipeline.queue.async {
                self.storeImageInCaches(response, isFromDiskCache: isFromDiskCache)
                self.send(value: response, isCompleted: isCompleted)
            }
        }
    }

    private func isDecompressionNeeded(for response: ImageResponse) -> Bool {
        (ImageDecompression.isDecompressionNeeded(for: response.image) ?? false) &&
        !request.options.contains(.skipDecompression) &&
        pipeline.delegate.shouldDecompress(response: response, for: request, pipeline: pipeline)
    }

    // MARK: Caching

    private func storeImageInCaches(_ response: ImageResponse, isFromDiskCache: Bool) {
        guard !isEphemeral else {
            return // Only store for direct requests
        }
        // Memory cache (ImageCaching)
        pipeline.cache[request] = response.container
        // Disk cache (DataCaching)
        if !isFromDiskCache {
            storeImageInDataCache(response)
        }
    }

    private func storeImageInDataCache(_ response: ImageResponse) {
        guard !response.container.isPreview else {
            return
        }
        guard let dataCache = pipeline.delegate.dataCache(for: request, pipeline: pipeline), shouldStoreImageInDiskCache() else {
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
            guard let data = encodedData else { return }
            pipeline.delegate.willCache(data: data, image: response.container, for: request, pipeline: pipeline) {
                guard let data = $0 else { return }
                // Important! Storing directly ignoring `ImageRequest.Options`.
                dataCache.storeData(data, for: key) // This is instant, writes are async
            }
        }
        if pipeline.configuration.debugIsSyncImageEncoding { // Only for debug
            pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()
        }
    }

    private func shouldStoreImageInDiskCache() -> Bool {
        guard !(request.url?.isLocalResource ?? false) else {
            return false
        }
        let isProcessed = !request.processors.isEmpty
        switch pipeline.configuration.dataCachePolicy {
        case .automatic:
            return isProcessed
        case .storeOriginalData:
            return false
        case .storeEncodedImages:
            return isProcessed || imageTasks.contains { $0.request.processors.isEmpty }
        case .storeAll:
            return isProcessed
        }
    }

    private var isEphemeral: Bool {
        !subscribers.contains { $0 is ImageTask }
    }
}
