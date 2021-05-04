// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

public extension ImagePipeline {
    typealias Delegate = ImagePipelineDelegate
}

public protocol ImagePipelineDelegate: AnyObject {
    // MARK: Caching

    /// Returns the image (in-memory) cache key for the given request.
    func makeImageCacheKey(for request: ImageRequest) -> ImagePipeline.CacheKey<AnyHashable>

    /// Returns the data cache (typically on-disk) key for the given request.
    func makeDataCacheKey(for request: ImageRequest) -> ImagePipeline.CacheKey<String>

    // MARK: Monitoring

    /// Delivers the events produced by the image tasks started via `loadImage` method.
    func imageTask(_ imageTask: ImageTask, didReceiveEvent event: ImageTaskEvent)
}

public extension ImagePipeline {
    enum CacheKey<T> {
        case `default`
        case custom(key: T)
    }
}

public extension ImagePipelineDelegate {
    func makeImageCacheKey(for request: ImageRequest) -> ImagePipeline.CacheKey<AnyHashable> {
        .default
    }

    func makeDataCacheKey(for request: ImageRequest) -> ImagePipeline.CacheKey<String> {
        .default
    }

    func imageTask(_ imageTask: ImageTask, didReceiveEvent event: ImageTaskEvent) {
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
