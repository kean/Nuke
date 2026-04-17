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
    @Sendable nonisolated func decode(
        _ context: ImageDecodingContext,
        using decoder: any ImageDecoding
    ) -> Result<ImageResponse, ImagePipeline.Error> {
        signpost(context.isCompleted ? "DecodeImageData" : "DecodeProgressiveImageData") {
            Result { try decoder.decode(context) }
                .mapError { .decodingFailed(decoder: decoder, context: context, error: $0) }
        }
    }

    @Sendable nonisolated func decode(
        _ context: ImageDecodingContext,
        using decoder: any AsyncImageDecoding
    ) async -> Result<ImageResponse, ImagePipeline.Error> {
        await signpost(context.isCompleted ? "DecodeImageData" : "DecodeProgressiveImageData") {
            do {
                return .success(try await decoder.decode(context))
            } catch {
                let mappedError = ImagePipeline.Error.decodingFailed(
                    decoder: decoder,
                    context: context,
                    error: error
                )
                
                return .failure(mappedError)
            }
        }
    }

    /// Decodes the data on the dedicated queue and calls the completion
    /// on the pipeline's internal queue.
    func decode(
        _ context: ImageDecodingContext,
        decoder: any BaseImageDecoding,
        _ completion: @escaping @ImagePipelineActor (Result<ImageResponse, ImagePipeline.Error>) -> Void
    ) {
        switch decoder {
            case let decoder as ImageDecoding where decoder.isAsynchronous:
                return completion(decode(context, using: decoder))
                
            case let decoder as ImageDecoding:
                operation = pipeline.configuration.imageDecodingQueue.add {
                    let imageContainer = await performInBackground {
                        self.decode(context, using: decoder)
                    }
                    
                    completion(imageContainer)
                }
                
            case let decoder as AsyncImageDecoding:
                operation = pipeline.configuration.imageDecodingQueue.add {
                    let imageContainer = await self.decode(context, using: decoder)
                    completion(imageContainer)
                }
                
            default:
                fatalError("Invalid BaseImageDecoding Implementation")
        }
    }
}
