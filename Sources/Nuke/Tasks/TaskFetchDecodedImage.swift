// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Receives data from ``TaskLoadImageData`` and decodes it as it arrives.
final class TaskFetchDecodedImage: ImagePipelineTask<ImageResponse> {
    private var decoder: (any ImageDecoding)?

    override func start() {
        dependency = pipeline.makeTaskFetchOriginalImageData(for: request).subscribe(self) { [weak self] in
            self?.didReceiveData($0.0, urlResponse: $0.1, isCompleted: $1)
        }
    }

    /// Receiving data from `OriginalDataTask`.
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

        let context = ImageDecodingContext(request: request, data: data, isCompleted: isCompleted, urlResponse: urlResponse, cacheType: nil)
        guard let decoder = getDecoder(for: context) else {
            if isCompleted {
                send(error: .decoderNotRegistered(context: context))
            } else {
                // Try again when more data is downloaded.
            }
            return
        }

        // Fast-track default decoders, most work is already done during
        // initialization anyway.
        @Sendable func decode() -> Result<ImageResponse, Error> {
            signpost("DecodeImageData", isCompleted ? "FinalImage" : "ProgressiveImage") {
                Result(catching: { try decoder.decode(context) })
            }
        }

        if !decoder.isAsynchronous {
            didFinishDecoding(decoder: decoder, context: context, result: decode())
        } else {
            operation = pipeline.configuration.imageDecodingQueue.add { [weak self] in
                guard let self = self else { return }

                let result = decode()
                self.pipeline.queue.async {
                    self.didFinishDecoding(decoder: decoder, context: context, result: result)
                }
            }
        }
    }

    private func didFinishDecoding(decoder: any ImageDecoding, context: ImageDecodingContext, result: Result<ImageResponse, Error>) {
        switch result {
        case .success(let response):
            send(value: response, isCompleted: context.isCompleted)
        case .failure(let error):
            if context.isCompleted {
                send(error: .decodingFailed(decoder: decoder, context: context, error: error))
            }
        }
    }

    // Lazily creates decoding for task
    private func getDecoder(for context: ImageDecodingContext) -> (any ImageDecoding)? {
        // Return the existing processor in case it has already been created.
        if let decoder = self.decoder {
            return decoder
        }
        let decoder = pipeline.delegate.imageDecoder(for: context, pipeline: pipeline)
        self.decoder = decoder
        return decoder
    }
}
