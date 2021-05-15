// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

public extension ImagePipeline {
    typealias Delegate = ImagePipelineDelegate
}

public protocol ImagePipelineDelegate: AnyObject {
    // MARK: Configuration

    /// Returns image decoder for the given context.
    func pipeline(_ pipeline: ImagePipeline, imageDecoderFor context: ImageDecodingContext) -> ImageDecoding?

    /// Returns image encoder for the given context.
    func pipeline(_ pipeline: ImagePipeline, imageEncoderFor context: ImageEncodingContext) -> ImageEncoding

    // MARK: Caching

    /// Returns the image (in-memory) cache key for the given request.
    func pipeline(_ pipeline: ImagePipeline, imageCacheKeyFor request: ImageRequest) -> ImagePipeline.CacheKey<AnyHashable>

    /// Returns the data cache (typically on-disk) key for the given request.
    func pipeline(_ pipeline: ImagePipeline, dataCacheKeyFor request: ImageRequest) -> ImagePipeline.CacheKey<String>

    // MARK: Monitoring

    /// Delivers the events produced by the image tasks started via `loadImage` method.
    func pipeline(_ pipeline: ImagePipeline, imageTask: ImageTask, didReceiveEvent event: ImageTaskEvent)
}

public extension ImagePipeline {
    enum CacheKey<T> {
        case `default`
        case custom(key: T)
    }
}

public extension ImagePipelineDelegate {
    func pipeline(_ pipeline: ImagePipeline, imageDecoderFor context: ImageDecodingContext) -> ImageDecoding? {
        pipeline.configuration.makeImageDecoder(context)
    }

    func pipeline(_ pipeline: ImagePipeline, imageEncoderFor context: ImageEncodingContext) -> ImageEncoding {
        pipeline.configuration.makeImageEncoder(context)
    }

    func pipeline(_ pipeline: ImagePipeline, imageCacheKeyFor request: ImageRequest) -> ImagePipeline.CacheKey<AnyHashable> {
        .default
    }

    func pipeline(_ pipeline: ImagePipeline, dataCacheKeyFor request: ImageRequest) -> ImagePipeline.CacheKey<String> {
        .default
    }

    func pipeline(_ pipeline: ImagePipeline, imageTask: ImageTask, didReceiveEvent event: ImageTaskEvent) {
        // Do nothing
    }
}

public enum ImageTaskEvent {
    case started
    case cancelled
    case priorityUpdated(priority: ImageRequest.Priority)
    case intermediateResponseReceived(response: ImageResponse)
    case progressUpdated(completedUnitCount: Int64, totalUnitCount: Int64)
    case completed(result: Result<ImageResponse, ImagePipeline.Error>)
}

extension ImageTaskEvent {
    init(_ event: Task<ImageResponse, ImagePipeline.Error>.Event) {
        switch event {
        case let .error(error):
            self = .completed(result: .failure(error))
        case let .value(response, isCompleted):
            if isCompleted {
                self = .completed(result: .success(response))
            } else {
                self = .intermediateResponseReceived(response: response)
            }
        case let .progress(progress):
            self = .progressUpdated(completedUnitCount: progress.completed, totalUnitCount: progress.total)
        }
    }
}

final class ImagePipelineDefaultDelegate: ImagePipelineDelegate {}
