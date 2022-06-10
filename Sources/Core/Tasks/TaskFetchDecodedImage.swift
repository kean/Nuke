// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Receives data from ``TaskLoadImageData` and decodes it as it arrives.
final class TaskFetchDecodedImage: ImagePipelineTask<ImageResponse> {
    private var decoder: ImageDecoding?

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

        let context = ImageDecodingContext(request: request, data: data, isCompleted: isCompleted, urlResponse: urlResponse)
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
        let decode = {
            signpost(log, "DecodeImageData", isCompleted ? "FinalImage" : "ProgressiveImage") {
                decoder.decode(data, urlResponse: urlResponse, isCompleted: isCompleted, cacheType: nil)
            }
        }
        if !decoder.isAsynchronous {
            self.didFinishDecoding(response: decode(), data: data, isCompleted: isCompleted)
        } else {
            operation = pipeline.configuration.imageDecodingQueue.add { [weak self] in
                guard let self = self else { return }

                let response = decode()
                self.async {
                    self.didFinishDecoding(response: response, data: data, isCompleted: isCompleted)
                }
            }
        }
    }

    private func didFinishDecoding(response: ImageResponse?, data: Data, isCompleted: Bool) {
        if let response = response {
            send(value: response, isCompleted: isCompleted)
        } else if isCompleted {
            send(error: .decodingFailed(data))
        }
    }

    // Lazily creates decoding for task
    private func getDecoder(for context: ImageDecodingContext) -> ImageDecoding? {
        // Return the existing processor in case it has already been created.
        if let decoder = self.decoder {
            return decoder
        }
        let decoder = pipeline.delegate.imageDecoder(for: context, pipeline: pipeline)
        self.decoder = decoder
        return decoder
    }
}
