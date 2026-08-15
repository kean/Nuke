// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

// Each task holds a strong reference to the pipeline. This is by design. The
// user does not need to hold a strong reference to the pipeline.
class AsyncPipelineTask<Value: Sendable>: AsyncTask<Value, ImagePipeline.Error> {
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
@ImagePipelineActor
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
    ///
    /// If the decoding is scheduled on the decoding queue, the operation is
    /// stored in ``AsyncTask/operation`` – it also serves as a back-pressure
    /// flag for the progressive decoding – and is cleared before the completion
    /// is called, so the callers never see a stale handle.
    func decode(_ context: ImageDecodingContext, decoder: any ImageDecoding, _ completion: @escaping @ImagePipelineActor (Result<ImageResponse, ImagePipeline.Error>) -> Void) {
        if let decoder = decoder as? any AsyncImageDecoding {
            operation = pipeline.configuration.imageDecodingQueue.add { [weak self] in
                let result: Result<ImageResponse, ImagePipeline.Error> = await signpost(context.isCompleted ? "DecodeImageData" : "DecodeProgressiveImageData") {
                    do {
                        return .success(try await decoder.decode(context))
                    } catch {
                        return .failure(.decodingFailed(decoder: decoder, context: context, error: error))
                    }
                }
                self?.operation = nil
                completion(result)
            }
            return
        }

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
            let result = await performInBackground(decode)
            self?.operation = nil
            completion(result)
        }
    }
}
