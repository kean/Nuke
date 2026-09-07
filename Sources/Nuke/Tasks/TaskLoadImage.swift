// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Wrapper for tasks created by `loadImage` calls.
///
/// Performs all the quick cache lookups and also manages image processing.
/// The coalescing for image processing is implemented on demand (extends the
/// scenarios in which coalescing can kick in).
final class TaskLoadImage: AsyncPipelineTask<ImageResponse> {
    override func start() {
        if let container = lookUpCachedImage(for: request) {
            let response = ImageResponse(container: container, request: request, cacheType: .memory)
            send(value: response, isCompleted: !container.isPreview)
            if !container.isPreview {
                return // The final image is loaded
            }
        }
        if let data = lookUpCachedData(for: request) {
            decodeCachedData(data)
        } else if request.thumbnail != nil, request.processors.isEmpty,
                  let data = lookUpCachedData(for: request.withoutThumbnail()) {
            decodeCachedData(data)
        } else {
            fetchImage()
        }
    }

    private func decodeCachedData(_ data: Data) {
        let context = ImageDecodingContext(request: request, data: data, cacheType: .disk, isAnimatedImageParsingEnabled: pipeline.configuration.isAnimatedImageParsingEnabled)
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
        let stage = diagnostics?.beginStage(.process, queued: true)
        let isRecording = stage != nil
        operation = pipeline.configuration.imageProcessingQueue.add { [weak self] in
            guard let self else { return }
            self.diagnostics?.startStage(stage)
            let (result, workDuration) = await performInBackground { () -> (Result<ImageResponse, ImagePipeline.Error>, Duration?) in
                let start: ContinuousClock.Instant? = isRecording ? .now : nil
                let result = signpost(isCompleted ? "ProcessImage" : "ProcessProgressiveImage") {
                    Result {
                        var response = response
                        response.container = try processor.process(response.container, context: context)
                        return response
                    }.mapError { error in
                        ImagePipeline.Error.processingFailed(processor: processor, context: context, error: error)
                    }
                }
                return (result, start.map { ContinuousClock.now - $0 })
            }
            self.operation = nil
            self.diagnostics?.endStage(stage) {
                $0.processor = processor.identifier
                $0.isProgressive = !isCompleted
                $0.workDuration = workDuration?.timeInterval
                if case .success(let response) = result {
                    $0.setOutput(response.container)
                }
            }
            self.didFinishProcessing(result: result, isCompleted: isCompleted)
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
        guard !isDisposed else { return }
        guard isDecompressionNeeded(for: response) else {
            return didReceiveDecompressedImage(response, isCompleted: isCompleted)
        }
        if isCompleted {
            operation?.cancel() // Cancel any potential pending progressive decompression tasks
        } else if operation != nil {
            return  // Back-pressure: receiving progressive scans too fast
        }
        let stage = diagnostics?.beginStage(.decompress, queued: true)
        let isRecording = stage != nil
        operation = pipeline.configuration.imageDecompressingQueue.add { [weak self] in
            guard let self else { return }
            self.diagnostics?.startStage(stage)
            let (response, workDuration) = await performInBackground { () -> (ImageResponse, Duration?) in
                let start: ContinuousClock.Instant? = isRecording ? .now : nil
                let response = signpost(isCompleted ? "DecompressImage" : "DecompressProgressiveImage") {
                    self.pipeline.delegate.decompress(response: response, request: self.request, pipeline: self.pipeline)
                }
                return (response, start.map { ContinuousClock.now - $0 })
            }
            self.operation = nil
            self.diagnostics?.endStage(stage) {
                $0.isProgressive = !isCompleted
                $0.workDuration = workDuration?.timeInterval
                $0.setOutput(response.container)
            }
            self.didReceiveDecompressedImage(response, isCompleted: isCompleted)
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
        let start: ContinuousClock.Instant? = diagnostics != nil ? .now : nil
        if pipeline.cache.storeCachedImageInMemoryCache(response.container, for: request), let start {
            diagnostics?.recordStage(.memoryStore, from: start) {
                $0.cacheKey = pipeline.cache.makeImageCacheKeyDigest(for: request)
                if response.isPreview {
                    $0.isProgressive = true
                }
            }
        }
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
        pipeline.configuration.imageEncodingQueue.add { [weak pipeline, request] in
            guard let pipeline else { return }
            let data = await performInBackground {
                signpost("EncodeImage") {
                    encoder.encode(response.container, context: context)
                }
            }
            guard let data, !data.isEmpty else { return }
            guard let data = await pipeline.willCache(data: data, image: response.container, for: request) else { return }
            // Important! Storing directly ignoring `ImageRequest.Options`.
            dataCache.storeData(data, for: key) // This is instant, writes are async
        }
    }

    private func shouldStoreResponseInDataCache(_ response: ImageResponse) -> Bool {
        guard !response.container.isPreview,
              !(response.cacheType == .disk) else {
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
        hasSubscriber(of: ImageTask.self)
    }
}
