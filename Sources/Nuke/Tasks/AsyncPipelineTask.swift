// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

// Each task holds a strong reference to the pipeline. This is by design. The
// user does not need to hold a strong reference to the pipeline.
class AsyncPipelineTask<Value: Sendable>: AsyncTask<Value, ImagePipeline.Error> {
    let pipeline: ImagePipeline
    // A canonical request representing the job performed by the task.
    let request: ImageRequest

    init(_ pipeline: ImagePipeline, _ request: ImageRequest, kind: ImagePipeline.Diagnostics.Job.Kind) {
        self.pipeline = pipeline
        self.request = request
        super.init()
        self.diagnostics = pipeline.recorder?.makeJobRecord(kind: kind, request: request)
    }
}

/// An image task, or a task that image tasks are subscribed to, directly or
/// through the tasks that depend on it.
@ImagePipelineActor
protocol ImageTaskSubscribers: AnyObject {
    /// Returns `true` if `predicate` returns `true` for any of the image tasks.
    ///
    /// The callers only ask whether there is one, so the walk stops at the
    /// first match instead of collecting the image tasks into an array.
    func containsImageTask(where predicate: (ImageTask) -> Bool) -> Bool
}

extension ImageTask: ImageTaskSubscribers {
    func containsImageTask(where predicate: (ImageTask) -> Bool) -> Bool {
        predicate(self)
    }
}

extension AsyncTask: ImageTaskSubscribers {
    func containsImageTask(where predicate: (ImageTask) -> Bool) -> Bool {
        containsSubscriber { $0.containsImageTask(where: predicate) }
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
            let stage = diagnostics?.beginStage(.decode, queued: true)
            operation = pipeline.configuration.imageDecodingQueue.add { [weak self] in
                self?.diagnostics?.startStage(stage)
                let start: ContinuousClock.Instant? = stage != nil ? .now : nil
                let result: Result<ImageResponse, ImagePipeline.Error> = await signpost(context.isCompleted ? "DecodeImageData" : "DecodeProgressiveImageData") {
                    do {
                        return .success(try await decoder.decode(context))
                    } catch {
                        return .failure(.decodingFailed(decoder: decoder, context: context, error: error))
                    }
                }
                self?.operation = nil
                self?.diagnostics?.endDecodeStage(stage, result: result, decoder: decoder, context: context, workDuration: start.map { (ContinuousClock.now - $0).timeInterval })
                completion(result)
            }
            return
        }

        let isRecording = diagnostics != nil
        @Sendable func decode() -> (Result<ImageResponse, ImagePipeline.Error>, TimeInterval?) {
            let start: ContinuousClock.Instant? = isRecording ? .now : nil
            let result: Result<ImageResponse, ImagePipeline.Error> = signpost(context.isCompleted ? "DecodeImageData" : "DecodeProgressiveImageData") {
                Result { try decoder.decode(context) }
                    .mapError { .decodingFailed(decoder: decoder, context: context, error: $0) }
            }
            return (result, start.map { (ContinuousClock.now - $0).timeInterval })
        }
        guard decoder.isAsynchronous else {
            let stage = diagnostics?.beginStage(.decode)
            let (result, workDuration) = decode()
            diagnostics?.endDecodeStage(stage, result: result, decoder: decoder, context: context, workDuration: workDuration)
            return completion(result)
        }
        let stage = diagnostics?.beginStage(.decode, queued: true)
        operation = pipeline.configuration.imageDecodingQueue.add { [weak self] in
            self?.diagnostics?.startStage(stage)
            let (result, workDuration) = await performInBackground(decode)
            self?.operation = nil
            self?.diagnostics?.endDecodeStage(stage, result: result, decoder: decoder, context: context, workDuration: workDuration)
            completion(result)
        }
    }
}

extension AsyncPipelineTask {
    /// Reads the memory cache, recording the lookup when diagnostics are on
    /// and there is a cache to look into.
    func lookUpCachedImage(for request: ImageRequest) -> ImageContainer? {
        guard let diagnostics else {
            return pipeline.cache[request]
        }
        guard !request.options.contains(.disableMemoryCacheReads),
              pipeline.delegate.imageCache(for: request, pipeline: pipeline) != nil else {
            return nil
        }
        let stage = diagnostics.beginStage(.memoryLookup)
        let container = pipeline.cache[request]
        diagnostics.endStage(stage) {
            $0.result = container == nil ? .miss : .hit
            $0.cacheKey = pipeline.cache.makeImageCacheKeyDigest(for: request)
            if container?.isPreview == true {
                $0.isProgressive = true
            }
        }
        return container
    }

    /// Reads the disk cache, recording the lookup when diagnostics are on and
    /// there is a cache to look into.
    func lookUpCachedData(for request: ImageRequest) -> Data? {
        guard let diagnostics else {
            return pipeline.cache.cachedData(for: request)
        }
        guard !request.options.contains(.disableDiskCacheReads),
              pipeline.delegate.dataCache(for: request, pipeline: pipeline) != nil else {
            return nil
        }
        let stage = diagnostics.beginStage(.diskLookup)
        let data = pipeline.cache.cachedData(for: request)
        diagnostics.endStage(stage) {
            $0.result = data == nil ? .miss : .hit
            $0.cacheKey = diagnosticsDigest(of: pipeline.cache.makeDataCacheKey(for: request))
            $0.bytes = data.map { Int64($0.count) }
        }
        return data
    }
}
