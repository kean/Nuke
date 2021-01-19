// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

final class DecompressedImageTask: Task<ImageResponse, ImagePipeline.Error> {
    private let context: ImagePipelineContext
    // TODO: cleanup
    private var configuration: ImagePipeline.Configuration { context.configuration }
    private var queue: DispatchQueue { context.queue }
    private let request: ImageRequest

    init(context: ImagePipelineContext, request: ImageRequest) {
        self.context = context
        self.request = request
    }

    func performDecompressedImageFetchTask(_ task: DecompressedImageTask, request: ImageRequest) {
        if let image = context.cachedImage(for: request) {
            let response = ImageResponse(container: image)
            if image.isPreview {
                task.send(value: response)
            } else {
                return task.send(value: response, isCompleted: true)
            }
        }

        guard let dataCache = configuration.dataCache, configuration.dataCacheOptions.storedItems.contains(.finalImage), request.cachePolicy != .reloadIgnoringCachedData else {
            return loadDecompressedImage()
        }

        // Load processed image from data cache and decompress it.
        let key = request.makeCacheKeyForFinalImageData()
        let operation = BlockOperation { [weak self] in
            guard let self = self else { return }

            let log = Log(self.context.log, "Read Cached Processed Image Data")
            log.signpost(.begin)
            let data = dataCache.cachedData(for: key)
            log.signpost(.end)

            self.queue.async {
                if let data = data {
                    self.decodeProcessedImageData(data)
                } else {
                    self.loadDecompressedImage()
                }
            }
        }
        task.operation = operation
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

            let log = Log(self.context.log, "Decode Cached Processed Image Data")
            log.signpost(.begin)
            let response = decoder.decode(data, urlResponse: nil, isCompleted: true)
            log.signpost(.end)

            self.queue.async {
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
        dependency = context.getProcessedImage(for: request).publisher.subscribe(self) { [weak self] image, isCompleted, _ in
            guard let self = self else { return }
            self.storeDecompressedImageInDataCache(image)
            self.decompressProcessedImage(image, isCompleted: isCompleted)
        }
    }

    #if os(macOS)
    func decompressProcessedImage(_ response: ImageResponse, isCompleted: Bool) {
        storeResponse(response.container, for: request)
        task.send(value: response, isCompleted: isCompleted) // There is no decompression on macOS
    }
    #else
    func decompressProcessedImage(_ response: ImageResponse, isCompleted: Bool) {
        guard isDecompressionNeeded(for: response) else {
            context.storeResponse(response.container, for: request)
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

            let log = Log(self.context.log, "Decompress Image")
            log.signpost(.begin, isCompleted ? "Final image" : "Progressive image")
            let response = response.map { $0.map(ImageDecompression.decompress(image:)) } ?? response
            log.signpost(.end)

            self.queue.async {
                self.context.storeResponse(response.container, for: self.request)
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
        configuration.imageEncodingQueue.addOperation { [weak self] in
            guard let self = self else { return }

            let log = Log(self.context.log, "Encode Image")
            log.signpost(.begin)
            let encodedData = encoder.encode(response.container, context: context)
            log.signpost(.end)

            guard let data = encodedData else { return }
            let key = self.request.makeCacheKeyForFinalImageData()
            dataCache.storeData(data, for: key) // This is instant
        }
    }
}
