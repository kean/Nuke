// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

final class DecompressedImageTask: ImagePipelineTask<ImageResponse> {
    override func start() {
        if let image = pipeline.cachedImage(for: request) {
            let response = ImageResponse(container: image)
            if image.isPreview {
                send(value: response)
            } else {
                return send(value: response, isCompleted: true)
            }
        }

        guard let dataCache = configuration.dataCache, configuration.dataCacheOptions.storedItems.contains(.finalImage), request.cachePolicy != .reloadIgnoringCachedData else {
            return loadDecompressedImage()
        }

        // Load processed image from data cache and decompress it.
        let key = request.makeCacheKeyForFinalImageData()
        let operation = BlockOperation { [weak self] in
            guard let self = self else { return }

            let log = Log(self.pipeline.log, "Read Cached Processed Image Data")
            log.signpost(.begin)
            let data = dataCache.cachedData(for: key)
            log.signpost(.end)

            self.pipeline.async {
                if let data = data {
                    self.decodeProcessedImageData(data)
                } else {
                    self.loadDecompressedImage()
                }
            }
        }
        self.operation = operation
        configuration.dataCachingQueue.addOperation(operation)
    }

    func decodeProcessedImageData(_ data: Data) {
        guard !isDisposed else { return }

        let decoderContext = ImageDecodingContext(request: request, data: data, isCompleted: true, urlResponse: nil)
        guard let decoder = configuration.makeImageDecoder(decoderContext) else {
            // This shouldn't happen in practice unless encoder/decoder pair
            // for data cache is misconfigured.
            return loadDecompressedImage()
        }

        let operation = BlockOperation { [weak self] in
            guard let self = self else { return }

            let log = Log(self.pipeline.log, "Decode Cached Processed Image Data")
            log.signpost(.begin)
            let response = decoder.decode(data, urlResponse: nil, isCompleted: true)
            log.signpost(.end)

            self.pipeline.async {
                if let response = response {
                    self.decompressProcessedImage(response, isCompleted: true)
                } else {
                    self.loadDecompressedImage()
                }
            }
        }
        self.operation = operation
        configuration.imageDecodingQueue.addOperation(operation)
    }

    func loadDecompressedImage() {
        dependency = pipeline.getProcessedImage(for: request).subscribe(self) { [weak self] image, isCompleted, _ in
            self?.storeDecompressedImageInDataCache(image)
            self?.decompressProcessedImage(image, isCompleted: isCompleted)
        }
    }

    #if os(macOS)
    func decompressProcessedImage(_ response: ImageResponse, isCompleted: Bool) {
        storeResponse(response.container)
        task.send(value: response, isCompleted: isCompleted) // There is no decompression on macOS
    }
    #else
    func decompressProcessedImage(_ response: ImageResponse, isCompleted: Bool) {
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

        let operation = BlockOperation { [weak self] in
            guard let self = self else { return }

            let log = Log(self.pipeline.log, "Decompress Image")
            log.signpost(.begin, isCompleted ? "Final image" : "Progressive image")
            let response = response.map { $0.map(ImageDecompression.decompress(image:)) } ?? response
            log.signpost(.end)

            self.pipeline.async {
                self.pipeline.storeResponse(response.container, for: self.request)
                self.send(value: response, isCompleted: isCompleted)
            }
        }
        self.operation = operation
        configuration.imageDecompressingQueue.addOperation(operation)
    }

    func isDecompressionNeeded(for response: ImageResponse) -> Bool {
        return configuration.isDecompressionEnabled &&
            ImageDecompression.isDecompressionNeeded(for: response.image) ?? false &&
            !(ImagePipeline.Configuration._isAnimatedImageDataEnabled && response.image._animatedImageData != nil)
    }
    #endif

    func storeDecompressedImageInDataCache(_ response: ImageResponse) {
        guard let dataCache = configuration.dataCache, configuration.dataCacheOptions.storedItems.contains(.finalImage) else {
            return
        }
        let context = ImageEncodingContext(request: request, image: response.image, urlResponse: response.urlResponse)
        let encoder = configuration.makeImageEncoder(context)
        configuration.imageEncodingQueue.addOperation {
            let log = Log(self.pipeline.log, "Encode Image")
            log.signpost(.begin)
            let encodedData = encoder.encode(response.container, context: context)
            log.signpost(.end)

            guard let data = encodedData else { return }
            let key = self.request.makeCacheKeyForFinalImageData()
            dataCache.storeData(data, for: key) // This is instant
        }
    }
}
