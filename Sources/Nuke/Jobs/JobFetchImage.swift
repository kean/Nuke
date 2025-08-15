// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

final class JobFetchImage2 {
    private let job: Job<ImageResponse>

    init(_ job: Job<ImageResponse>) {
        self.job = job
    }
}

/// Wrapper for tasks created by `loadImage` calls.
///
/// Performs all the quick cache lookups and also manages image processing.
/// The coalescing for image processing is implemented on demand (extends the
/// scenarios in which coalescing can kick in).
class JobFetchImage: AsyncPipelineTask<ImageResponse>, JobSubscriber {
    private var decoder: (any ImageDecoding)?

    // MARK: Memory Cache

    override func start() {
        dependency = pipeline.makeJobFetchData(for: request).subscribe(self)
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
            operation?.unsubscribe() // Cancel any potential pending progressive decoding tasks
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

    private func didFinishDecoding(context: ImageDecodingContext, result: Result<ImageResponse, ImageTask.Error>) {
        operation = nil // TODO: cleanup

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
            operation?.unsubscribe() // Cancel any potential pending progressive
        } else if operation != nil {
            return // Back pressure - already processing another progressive image
        }
        guard !request.processors.isEmpty else {
            return didReceiveProcessedImage(response, isCompleted: isCompleted)
        }
        let context = ImageProcessingContext(request: request, response: response, isCompleted: isCompleted)
        process(context, response: response, processors: request.processors) { [weak self] in
            self?.operation = nil
            self?.didFinishProcessing(result: $0, isCompleted: isCompleted)
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
            operation?.unsubscribe() // Cancel any potential pending progressive decompression tasks
        } else if operation != nil {
            return  // Back-pressure: receiving progressive scans too fast
        }
        decompress(response) { response in
            self.operation = nil
            self.didReceiveDecompressedImage(response, isCompleted: isCompleted)
        }
    }

    // TODO: do it based on the subscribed tasks
    private func isDecompressionNeeded(for response: ImageResponse) -> Bool {
        ImageDecompression.isDecompressionNeeded(for: response) &&
        !request.options.contains(.skipDecompression) &&
        pipeline.delegate.shouldDecompress(response: response, for: request, pipeline: pipeline)
    }

    private func didReceiveDecompressedImage(_ response: ImageResponse, isCompleted: Bool) {
        send(value: response, isCompleted: isCompleted)
    }
}
