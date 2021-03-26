// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Tries to load processed image data from disk and if not available, starts
/// `ProcessedImageTask` and subscribes to it.
final class TaskLoadImage: ImagePipelineTask<ImageResponse> {
    override func start() {
        if let image = pipeline.cachedImage(for: request) {
            let response = ImageResponse(container: image)
            if image.isPreview {
                send(value: response)
            } else {
                return send(value: response, isCompleted: true)
            }
        }

        guard let dataCache = pipeline.configuration.dataCache, pipeline.configuration.dataCacheOptions.storedItems.contains(.finalImage), request.cachePolicy != .reloadIgnoringCachedData else {
            return loadDecompressedImage()
        }

        // Load processed image from data cache and decompress it.
        operation = pipeline.configuration.dataCachingQueue.add { [weak self] in
            self?.getCachedData(dataCache: dataCache)
        }
    }

    private func getCachedData(dataCache: DataCaching) {
        let key = request.makeCacheKeyForFinalImageData()
        let data = signpost(log, "ReadCachedProcessedImageData") {
            dataCache.cachedData(for: key)
        }
        async {
            if let data = data {
                self.decodeProcessedImageData(data)
            } else {
                self.loadDecompressedImage()
            }
        }
    }

    private func decodeProcessedImageData(_ data: Data) {
        guard !isDisposed else { return }

        let decoderContext = ImageDecodingContext(request: request, data: data, isCompleted: true, urlResponse: nil)
        guard let decoder = pipeline.configuration.makeImageDecoder(decoderContext) else {
            // This shouldn't happen in practice unless encoder/decoder pair
            // for data cache is misconfigured.
            return loadDecompressedImage()
        }

        operation = pipeline.configuration.imageDecodingQueue.add { [weak self] in
            guard let self = self else { return }
            let response = signpost(log, "DecodeCachedProcessedImageData") {
                decoder.decode(data, urlResponse: nil, isCompleted: true)
            }
            self.async {
                if let response = response {
                    self.decompressProcessedImage(response, isCompleted: true)
                } else {
                    self.loadDecompressedImage()
                }
            }
        }
    }

    private func loadDecompressedImage() {
        dependency = pipeline.makeTaskProcessImage(for: request).subscribe(self) { [weak self] in
            self?.storeImageInDataCache($0)
            self?.decompressProcessedImage($0, isCompleted: $1)
        }
    }

    #if os(macOS)
    private func decompressProcessedImage(_ response: ImageResponse, isCompleted: Bool) {
        pipeline.storeResponse(response.container, for: request)
        send(value: response, isCompleted: isCompleted) // There is no decompression on macOS
    }
    #else
    private func decompressProcessedImage(_ response: ImageResponse, isCompleted: Bool) {
        guard isDecompressionNeeded(for: response) else {
            pipeline.storeResponse(response.container, for: request)
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
                self.pipeline.storeResponse(response.container, for: self.request)
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

    private func storeImageInDataCache(_ response: ImageResponse) {
        guard let dataCache = pipeline.configuration.dataCache, pipeline.configuration.dataCacheOptions.storedItems.contains(.finalImage), !response.container.isPreview else {
            return
        }
        let context = ImageEncodingContext(request: request, image: response.image, urlResponse: response.urlResponse)
        let encoder = pipeline.configuration.makeImageEncoder(context)
        pipeline.configuration.imageEncodingQueue.addOperation { [request, log] in
            let encodedData = signpost(log, "EncodeImage") {
                encoder.encode(response.container, context: context)
            }
            guard let data = encodedData else { return }
            let key = request.makeCacheKeyForFinalImageData()
            dataCache.storeData(data, for: key) // This is instant
        }
    }
}
