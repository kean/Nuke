// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Wrapper for tasks created by `loadImage` calls.
///
/// Performs all the quick cache lookups and also manages image processing.
/// The coalescing for image processing is implemented on demand (extends the
/// scenarios in which coalescing can kick in).
final class JobFetchImage: AsyncPipelineTask<ImageResponse>, JobSubscriber {
    private var decoder: (any ImageDecoding)?

    // MARK: Memory Cache

    override func start() {
        if let container = pipeline.cache[request] {
            let response = ImageResponse(container: container, request: request, cacheType: .memory)
            send(value: response, isCompleted: !container.isPreview)
            if !container.isPreview {
                return // The final image is loaded
            }
        }
        // TODO: check original image cache also!
        if let data = pipeline.cache.cachedData(for: request) {
            decodeCachedData(data)
        } else {
            fetchImage()
        }
    }

    // MARK: Disk Cache

    private func decodeCachedData(_ data: Data) {
        let context = ImageDecodingContext(request: request, data: data, cacheType: .disk)
        guard let decoder = pipeline.delegate.imageDecoder(for: context, pipeline: pipeline) else {
            return didFinishDecoding(with: nil)
        }
        decode(context, decoder: decoder) { [weak self] result in
            self?.didFinishDecoding(with: try? result.get())
        }
    }

    private func didFinishDecoding(with response: ImageResponse?) {
        if let response {
            didReceiveProcessedImage(response, isCompleted: true)
        } else {
            fetchImage()
        }
    }

    // MARK: Fetch Image

    private func fetchImage() {
        guard !request.options.contains(.returnCacheDataDontLoad) else {
            return send(error: .dataMissingInCache)
        }
        dependency = pipeline.makeTaskFetchOriginalData(for: request).subscribe(self)
    }

    func receive(_ event: Job<(Data, URLResponse?)>.Event) {
        switch event {
        case let .value(value, isCompleted):
            didReceiveData(value.0, urlResponse: value.1, isCompleted: isCompleted)
        case .progress(let progress):
            send(progress: progress)
        case .error(let error):
            send(error: error)
        }
    }

    /// Receiving data from `TaskFetchOriginalData`.
    private func didReceiveData(_ data: Data, urlResponse: URLResponse?, isCompleted: Bool) {
        guard isCompleted || pipeline.configuration.isProgressiveDecodingEnabled else {
            return
        }

        if !isCompleted && operation != nil {
            return // Back pressure - already decoding another progressive data chunk
        }

        if isCompleted {
            operation?.cancel() // Cancel any potential pending progressive decoding tasks

            storeDataInCacheIfNeeded(data)
        }

        let context = ImageDecodingContext(request: request, data: data, isCompleted: isCompleted, urlResponse: urlResponse)
        guard let decoder = getDecoder(for: context) else {
            if isCompleted {
                send(error: .decoderNotRegistered(context: context))
            } else {
                // Try again when more data is downloaded.
            }
            return
        }
        decode(context, decoder: decoder) { [weak self] result in
            self?.didFinishDecoding(context: context, result: result)
        }
    }

    private func decode(_ context: ImageDecodingContext, decoder: any ImageDecoding, _ completion: @ImagePipelineActor @Sendable @escaping (Result<ImageResponse, ImageTask.Error>) -> Void) {
        @Sendable func decode() -> Result<ImageResponse, ImageTask.Error> {
            signpost(context.isCompleted ? "DecodeImageData" : "DecodeProgressiveImageData") {
                Result { try decoder.decode(context) }
                    .mapError { .decodingFailed(decoder: decoder, context: context, error: $0) }
            }
        }
        guard decoder.isAsynchronous else {
            return completion(decode())
        }
        operation = pipeline.configuration.imageDecodingQueue.add(priority: priority) {
            let response = await performInBackground { decode() }
            completion(response)
        }
    }

    private func didFinishDecoding(context: ImageDecodingContext, result: Result<ImageResponse, ImageTask.Error>) {
        operation = nil

        switch result {
        case .success(let response):
            didReceiveDecodedImage(response, isCompleted: context.isCompleted)
        case .failure(let error):
            if context.isCompleted {
                send(error: error)
            }
        }
    }

    // Lazily creates decoding for task
    private func getDecoder(for context: ImageDecodingContext) -> (any ImageDecoding)? {
        // Return the existing processor in case it has already been created.
        if let decoder {
            return decoder
        }
        let decoder = pipeline.delegate.imageDecoder(for: context, pipeline: pipeline)
        self.decoder = decoder
        return decoder
    }

    // MARK: Processing

    private func didReceiveDecodedImage(_ response: ImageResponse, isCompleted: Bool) {
        guard !isDisposed else { return }
        if isCompleted {
            operation?.cancel() // Cancel any potential pending progressive
        } else if operation != nil {
            return // Back pressure - already processing another progressive image
        }
        let processors = request.processors
        guard !processors.isEmpty else {
            return didReceiveProcessedImage(response, isCompleted: isCompleted)
        }
        let context = ImageProcessingContext(request: request, response: response, isCompleted: isCompleted)
        operation = pipeline.configuration.imageProcessingQueue.add(priority: priority) { [weak self] in
            guard let self else { return }
            let result: Result<ImageResponse, ImageTask.Error> = await performInBackground {
                signpost(isCompleted ? "ProcessImage" : "ProcessProgressiveImage") {
                    var response = response
                    for processor in processors {
                        do {
                            response.container = try processor.process(response.container, context: context)
                        } catch {
                            return .failure(.processingFailed(processor: processor, context: context, error: error))
                        }
                    }
                    return .success(response)
                }
            }
            self.operation = nil
            self.didFinishProcessing(result: result, isCompleted: isCompleted)
        }
    }

    private func didFinishProcessing(result: Result<ImageResponse, ImageTask.Error>, isCompleted: Bool) {
        switch result {
        case .success(let response):
            didReceiveProcessedImage(response, isCompleted: isCompleted)
        case .failure(let error):
            if isCompleted {
                send(error: error)
            }
        }
    }

    // MARK: Decompression

    private func didReceiveProcessedImage(_ response: ImageResponse, isCompleted: Bool) {
        guard isDecompressionNeeded(for: response) else {
            return didReceiveDecompressedImage(response, isCompleted: isCompleted)
        }
        guard !isDisposed else { return }
        if isCompleted {
            operation?.cancel() // Cancel any potential pending progressive decompression tasks
        } else if operation != nil {
            return  // Back-pressure: receiving progressive scans too fast
        }
        operation = pipeline.configuration.imageDecompressingQueue.add(priority: priority) { [weak self] in
            guard let self else { return }
            let response = await performInBackground {
                signpost(isCompleted ? "DecompressImage" : "DecompressProgressiveImage") {
                    self.pipeline.delegate.decompress(response: response, request: self.request, pipeline: self.pipeline)
                }
            }
            self.operation = nil
            self.didReceiveDecompressedImage(response, isCompleted: isCompleted)
        }
    }

    private func isDecompressionNeeded(for response: ImageResponse) -> Bool {
        ImageDecompression.isDecompressionNeeded(for: response) &&
        !request.options.contains(.skipDecompression) &&
        pipeline.delegate.shouldDecompress(response: response, for: request, pipeline: pipeline)
    }

    private func didReceiveDecompressedImage(_ response: ImageResponse, isCompleted: Bool) {
        storeImageInCaches(response)
        send(value: response, isCompleted: isCompleted)
    }
}
