// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Performs all the quick cache lookups and also manages image processing.
/// The coalesing for image processing is implemented on demand (extends the
/// scenarios in which coalescing can kick in).
final class TaskLoadImage: ImagePipelineTask<ImageResponse> {
    override func start() {
        if let image = pipeline.cache.cachedImage(for: request) {
            let response = ImageResponse(container: image)
            if image.isPreview {
                send(value: response)
            } else {
                return send(value: response, isCompleted: true)
            }
        }

        guard let dataCache = pipeline.configuration.dataCache,
              request.cachePolicy != .reloadIgnoringCachedData else {
            return loadImage()
        }

        // Load processed image from data cache and decompress it.
        operation = pipeline.configuration.dataCachingQueue.add { [weak self] in
            self?.getCachedData(dataCache: dataCache)
        }
    }

    private func getCachedData(dataCache: DataCaching) {
        let data = signpost(log, "ReadCachedProcessedImageData") {
            pipeline.cache.cachedData(for: request)
        }
        async {
            if let data = data {
                self.decodeProcessedImageData(data)
            } else {
                self.loadImage()
            }
        }
    }

    // MARK: Decoding Processed Images

    private func decodeProcessedImageData(_ data: Data) {
        guard !isDisposed else { return }

        let context = ImageDecodingContext(request: request, data: data, isCompleted: true, urlResponse: nil)
        guard let decoder = pipeline.configuration.makeImageDecoder(context) else {
            // This shouldn't happen in practice unless encoder/decoder pair
            // for data cache is misconfigured.
            return loadImage()
        }

        let decode = {
            signpost(log, "DecodeCachedProcessedImageData") {
                decoder.decode(data, urlResponse: nil, isCompleted: true)
            }
        }
        if ImagePipeline.Configuration.isFastTrackDecodingEnabled(for: decoder) {
            didFinishDecodingProcessedImageData(decode())
        } else {
            operation = pipeline.configuration.imageDecodingQueue.add { [weak self] in
                guard let self = self else { return }
                let response = decode()
                self.async {
                    self.didFinishDecodingProcessedImageData(response)
                }
            }
        }
    }

    private func didFinishDecodingProcessedImageData(_ response: ImageResponse?) {
        if let response = response {
            decompressProcessedImage(response, isCompleted: true)
        } else {
            loadImage()
        }
    }

    // MARK: Loading Original Image + Processing

    private func loadImage() {
        // Check if any of the intermediate processed images (or the original image)
        // available in the memory cache.
        var current = request.processors
        var remaining: [ImageProcessing] = []
        while !current.isEmpty {
            let request = self.request.withProcessors(current)
            if let image = pipeline.cache.cachedImage(for: request), !image.isPreview {
                didReceiveImage(ImageResponse(container: image), isCompleted: true, processors: remaining)
                return
            }
            if let last = current.popLast() {
                remaining.append(last)
            }
        }

        if request.cachePolicy == .returnCacheDataDontLoad {
            // Same error that URLSession produces when .returnCacheDataDontLoad is specified and the
            // data is no found in the cache.
            let error = NSError(domain: URLError.errorDomain, code: URLError.resourceUnavailable.rawValue, userInfo: nil)
            send(error: .dataLoadingFailed(error))
        } else if request.processors.isEmpty {
            dependency = pipeline.makeTaskDecodeImage(for: request).subscribe(self) { [weak self] in
                self?.didReceiveImage($0, isCompleted: $1, processors: remaining)
            }
        } else {
            let request = self.request.withProcessors([])
            dependency = pipeline.makeTaskLoadImage(for: request).subscribe(self) { [weak self] in
                self?.didReceiveImage($0, isCompleted: $1, processors: remaining)
            }
        }
    }

    private func didReceiveImage(_ response: ImageResponse, isCompleted: Bool, processors: [ImageProcessing]) {
        guard !(ImagePipeline.Configuration._isAnimatedImageDataEnabled && response.image._animatedImageData != nil) else {
            self.didProduceProcessedImage(response, isCompleted: isCompleted)
            return
        }

        if isCompleted {
            dependency2?.unsubscribe() // Cancel any potential pending progressive processing tasks
        } else if dependency2 != nil {
            return  // Back pressure - already processing another progressive image
        }

        _processImage(response, isCompleted: isCompleted, processors: processors)
    }

    private func _processImage(_ response: ImageResponse, isCompleted: Bool, processors: [ImageProcessing]) {
        dependency2 = nil

        guard let processor = processors.last else {
            self.didProduceProcessedImage(response, isCompleted: isCompleted)
            return
        }

        let key = ImageProcessingKey(image: response, processor: processor)
        dependency2 = pipeline.makeTaskProcessImage(key: key, process: {
            let context = ImageProcessingContext(request: self.request, response: response, isFinal: isCompleted)
            return signpost(log, "ProcessImage", isCompleted ? "FinalImage" : "ProgressiveImage") {
                response.map { processor.process($0, context: context) }
            }
        }).subscribe(priority: priority) { [weak self] event in
            guard let self = self else { return }
            switch event {
            case .value(let response, _):
                self._processImage(response, isCompleted: isCompleted, processors: processors.dropLast())
            case .error:
                if isCompleted {
                    self.send(error: .processingFailed)
                }
            case .progress:
                break // Do nothing
            }
        }
    }

    private func didProduceProcessedImage(_ response: ImageResponse, isCompleted: Bool) {
        storeImageInDataCache(response)
        decompressProcessedImage(response, isCompleted: isCompleted)
    }

    // MARK: Decompression

    #if os(macOS)
    private func decompressProcessedImage(_ response: ImageResponse, isCompleted: Bool) {
        pipeline.cache.storeCachedImage(response.container, for: request)
        send(value: response, isCompleted: isCompleted) // There is no decompression on macOS
    }
    #else
    private func decompressProcessedImage(_ response: ImageResponse, isCompleted: Bool) {
        guard isDecompressionNeeded(for: response) else {
            pipeline.cache.storeCachedImage(response.container, for: request)
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
            guard let self = self else { return }

            let response = signpost(log, "DecompressImage", isCompleted ? "FinalImage" : "ProgressiveImage") {
                response.map { $0.map(ImageDecompression.decompress(image:)) } ?? response
            }

            self.async {
                self.pipeline.cache.storeCachedImage(response.container, for: self.request)
                self.send(value: response, isCompleted: isCompleted)
            }
        }
    }

    private func isDecompressionNeeded(for response: ImageResponse) -> Bool {
        return pipeline.configuration.isDecompressionEnabled &&
            ImageDecompression.isDecompressionNeeded(for: response.image) ?? false &&
            !(ImagePipeline.Configuration._isAnimatedImageDataEnabled && response.image._animatedImageData != nil)
    }
    #endif

    // MARK: Caching

    private func storeImageInDataCache(_ response: ImageResponse) {
        guard !response.container.isPreview else {
            return
        }
        guard let dataCache = pipeline.configuration.dataCache, shouldStoreFinalImageInDiskCache() else {
            return
        }
        let context = ImageEncodingContext(request: request, image: response.image, urlResponse: response.urlResponse)
        let encoder = pipeline.configuration.makeImageEncoder(context)
        let key = pipeline.cache.makeDataCacheKey(for: request)
        pipeline.configuration.imageEncodingQueue.addOperation {
            let encodedData = signpost(log, "EncodeImage") {
                encoder.encode(response.container, context: context)
            }
            guard let data = encodedData else { return }
            dataCache.storeData(data, for: key) // This is instant
        }
        #warning("should it always be sync?")
        if pipeline.configuration.debugIsSyncImageEncoding { // Only for debug
            pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()
        }
    }

    private func shouldStoreFinalImageInDiskCache() -> Bool {
        guard request.url?.isCacheable ?? false else {
            return false
        }
        guard subscribers.contains(where: { $0 is ImageTask }) else {
            return false // This a virtual task
        }
        let policy = pipeline.configuration.diskCachePolicy
        return ((policy == .automatic && !request.processors.isEmpty) || policy == .storeEncodedImages)
    }
}
