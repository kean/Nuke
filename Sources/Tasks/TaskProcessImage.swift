// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Receives images from `TaskDecodeImage` or intermidiate `TaskProcessImage`
/// and applies respective processors.
final class TaskProcessImage: ImagePipelineTask<ImageResponse> {
    override func start() {
        assert(!request.processors.isEmpty)
        guard !isDisposed, !request.processors.isEmpty else { return }

        if let image = pipeline.cachedImage(for: request), !image.isPreview {
            return send(value: ImageResponse(container: image), isCompleted: true)
        }

        let processor: ImageProcessing
        var subRequest = request
        if pipeline.configuration.isDeduplicationEnabled {
            // Recursively call getProcessedImage until there are no more processors left.
            // Each time getProcessedImage is called it tries to find an existing
            // task ("deduplication") to avoid doing any duplicated work.
            processor = request.processors.last!
            subRequest.processors = Array(request.processors.dropLast())
        } else {
            // Perform all transformations in one go
            processor = ImageProcessors.Composition(request.processors)
            subRequest.processors = []
        }
        dependency = pipeline.makeTaskProcessImage(for: subRequest).subscribe(self) { [weak self] in
            self?.processImage($0, isCompleted: $1, processor: processor)
        }
    }

    private func processImage(_ response: ImageResponse, isCompleted: Bool, processor: ImageProcessing) {
        guard !(ImagePipeline.Configuration._isAnimatedImageDataEnabled && response.image._animatedImageData != nil) else {
            send(value: response, isCompleted: isCompleted)
            return
        }

        if isCompleted {
            operation?.cancel() // Cancel any potential pending progressive processing tasks
        } else if operation != nil {
            return  // Back pressure - already processing another progressive image
        }

        operation = pipeline.configuration.imageProcessingQueue.add { [weak self] in
            guard let self = self else { return }

            let context = ImageProcessingContext(request: self.request, response: response, isFinal: isCompleted)
            let response = signpost(log, "ProcessImage", isCompleted ? "FinalImage" : "ProgressiveImage") {
                response.map { processor.process($0, context: context) }
            }

            self.async {
                guard let response = response else {
                    if isCompleted {
                        self.send(error: .processingFailed)
                    } // Ignore when progressive processing fails
                    return
                }
                self.send(value: response, isCompleted: isCompleted)
            }
        }
    }
}
