// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Receives data from ``TaskLoadImageData`` and decodes it as it arrives.
final class TaskFetchOriginalImage: AsyncPipelineTask<ImageResponse>, @unchecked Sendable {
    private var decoder: (any ImageDecoding)?

    override func start() {
        dependency = pipeline.makeTaskFetchOriginalData(for: request).subscribe(self) { [weak self] in
            self?.didReceiveData($0.0, urlResponse: $0.1, isCompleted: $1)
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

        decode(context, decoder: decoder) { [weak self] in
            self?.didFinishDecoding(context: context, result: $0)
        }
    }

    private func didFinishDecoding(context: ImageDecodingContext, result: Result<ImageResponse, ImagePipeline.Error>) {
        operation = nil

        switch result {
        case .success(let response):
            send(value: response, isCompleted: context.isCompleted)
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
}
