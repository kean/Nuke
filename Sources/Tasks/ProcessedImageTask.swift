// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

final class ProcessedImageTask: Task<ImageResponse, ImagePipeline.Error> {
    private let context: ImagePipelineContext
    // TODO: cleanup
    private var configuration: ImagePipeline.Configuration { context.configuration }
    private var queue: DispatchQueue { context.queue }
    private let request: ImageRequest

    init(context: ImagePipelineContext, request: ImageRequest) {
        self.context = context
        self.request = request
    }

    override func start() {
        // TODO: cleanup task creation, we should do that on start, should we?

        assert(!request.processors.isEmpty)
        guard !isDisposed, !request.processors.isEmpty else { return }

        if let image = context.cachedImage(for: request), !image.isPreview {
            return send(value: ImageResponse(container: image), isCompleted: true)
        }

        let processor: ImageProcessing
        var subRequest = request
        if configuration.isDeduplicationEnabled {
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
        dependency = context.getProcessedImage(for: subRequest).publisher
            .subscribe(self) { [weak self] image, isCompleted, _ in
                self?.processImage(image, isCompleted: isCompleted, processor: processor, request: subRequest)
            }
    }

    func processImage(_ response: ImageResponse, isCompleted: Bool, processor: ImageProcessing, request: ImageRequest) {
        guard !(ImagePipeline.Configuration._isAnimatedImageDataEnabled && response.image._animatedImageData != nil) else {
            send(value: response, isCompleted: isCompleted)
            return
        }

        if isCompleted {
            operation?.cancel() // Cancel any potential pending progressive processing tasks
        } else if operation != nil {
            return  // Back pressure - already processing another progressive image
        }

        let operation = BlockOperation { [weak self] in
            guard let self = self else { return }

            let log = Log(self.context.log, "Process Image")
            log.signpost(.begin, "\(processor), \(isCompleted ? "final" : "progressive") image")
            let context = ImageProcessingContext(request: self.request, response: response, isFinal: isCompleted)
            let response = response.map { processor.process($0, context: context) }
            log.signpost(.end)

            self.queue.async {
                guard let response = response else {
                    if isCompleted {
                        self.send(error: .processingFailed)
                    } // Ignore when progressive processing fails
                    return
                }
                self.send(value: response, isCompleted: isCompleted)
            }
        }
        self.operation = operation
        configuration.imageProcessingQueue.addOperation(operation)
    }
}
