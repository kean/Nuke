// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

final class OriginalImageTask: ImagePipelineTask<ImageResponse> {
    private var decoder: ImageDecoding?

    override func start() {
        dependency = pipeline.getOriginalImageData(for: request)
            .subscribe(self) { [weak self] value, isCompleted in
            self?.on(value, isCompleted: isCompleted)
        }
    }

    func on(_ value: (Data, URLResponse?), isCompleted: Bool) {
        let (data, urlResponse) = value
        if isCompleted {
            operation?.cancel() // Cancel any potential pending progressive decoding tasks
        } else if !configuration.isProgressiveDecodingEnabled || operation != nil {
            return // Back pressure - already decoding another progressive data chunk
        }

        // Sanity check
        guard !data.isEmpty else {
            if isCompleted {
                send(error: .decodingFailed)
            }
            return
        }

        guard let decoder = self.decoder(data: data, urlResponse: urlResponse, isCompleted: isCompleted) else {
            if isCompleted {
                send(error: .decodingFailed)
            } // Try again when more data is downloaded.
            return
        }

        let operation = BlockOperation { [weak self] in
            guard let self = self else { return }

            let log = Log(self.pipeline.log, "Decode Image Data")
            log.signpost(.begin, "\(isCompleted ? "Final" : "Progressive") image")
            let response = decoder.decode(data, urlResponse: urlResponse, isCompleted: isCompleted)
            log.signpost(.end)

            self.pipeline.async {
                if let response = response {
                    self.send(value: response, isCompleted: isCompleted)
                } else if isCompleted {
                    self.send(error: .decodingFailed)
                }
            }
        }
        self.operation = operation
        configuration.imageDecodingQueue.addOperation(operation)
    }

    // Lazily creates decoding for task
    func decoder(data: Data, urlResponse: URLResponse?, isCompleted: Bool) -> ImageDecoding? {
        // Return the existing processor in case it has already been created.
        if let decoder = self.decoder {
            return decoder
        }
        let decoderContext = ImageDecodingContext(request: request, data: data, isCompleted: isCompleted, urlResponse: urlResponse)
        let decoder = configuration.makeImageDecoder(decoderContext)
        self.decoder = decoder
        return decoder
    }
}
