// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation

// Each task holds a strong reference to the pipeline. This is by design. The
// user does not need to hold a strong reference to the pipeline.
class AsyncPipelineTask<Value: Sendable>: AsyncTask<Value, ImagePipeline.Error>, @unchecked Sendable {
    let pipeline: ImagePipeline
    // A canonical request representing the unit work performed by the task.
    let request: ImageRequest

    init(_ pipeline: ImagePipeline, _ request: ImageRequest) {
        self.pipeline = pipeline
        self.request = request
    }
}

// Returns all image tasks subscribed to the current pipeline task.
// A suboptimal approach just to make the new DiskCachPolicy.automatic work.
protocol ImageTaskSubscribers {
    var imageTasks: [ImageTask] { get }
}

extension ImageTask: ImageTaskSubscribers {
    var imageTasks: [ImageTask] {
        [self]
    }
}

extension AsyncPipelineTask: ImageTaskSubscribers {
    var imageTasks: [ImageTask] {
        subscribers.flatMap { subscribers -> [ImageTask] in
            (subscribers as? ImageTaskSubscribers)?.imageTasks ?? []
        }
    }
}

extension AsyncPipelineTask {
    /// Decodes the data on the dedicated queue and calls the completion
    /// on the pipeline's internal queue.
    func decode(_ context: ImageDecodingContext, decoder: any ImageDecoding, _ completion: @Sendable @escaping (Result<ImageResponse, ImagePipeline.Error>) -> Void) {
        @Sendable func decode() -> Result<ImageResponse, ImagePipeline.Error> {
            signpost(context.isCompleted ? "DecodeImageData" : "DecodeProgressiveImageData") {
                Result { try decoder.decode(context) }
                    .mapError { .decodingFailed(decoder: decoder, context: context, error: $0) }
            }
        }
        guard decoder.isAsynchronous else {
            return completion(decode())
        }
        operation = pipeline.configuration.imageDecodingQueue.add { [weak self] in
            guard let self else { return }
            let response = decode()
            self.pipeline.queue.async {
                completion(response)
            }
        }
    }
}
