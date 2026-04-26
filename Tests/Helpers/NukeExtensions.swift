// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

extension ImagePipeline.Error: @retroactive Equatable {
    public static func == (lhs: ImagePipeline.Error, rhs: ImagePipeline.Error) -> Bool {
        switch (lhs, rhs) {
        case (.dataMissingInCache, .dataMissingInCache),
             (.dataIsEmpty, .dataIsEmpty),
             (.imageRequestMissing, .imageRequestMissing),
             (.pipelineInvalidated, .pipelineInvalidated),
             (.dataDownloadExceededMaximumSize, .dataDownloadExceededMaximumSize),
             (.cancelled, .cancelled),
             (.decoderNotRegistered, .decoderNotRegistered),
             (.decodingFailed, .decodingFailed),
             (.processingFailed, .processingFailed):
            return true
        case let (.dataLoadingFailed(lhs), .dataLoadingFailed(rhs)):
            return lhs as NSError == rhs as NSError
        default:
            return false
        }
    }
}

extension ImageTask.Event: @retroactive Equatable {
    public static func == (lhs: ImageTask.Event, rhs: ImageTask.Event) -> Bool {
        switch (lhs, rhs) {
        case let (.progress(lhs), .progress(rhs)):
            return lhs == rhs
        case let (.preview(lhs), .preview(rhs)):
            return lhs == rhs
        case let (.finished(lhs), .finished(rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}

extension ImageResponse: @retroactive Equatable {
    public static func == (lhs: ImageResponse, rhs: ImageResponse) -> Bool {
        return lhs.image === rhs.image
    }
}

extension ImageRequest {
    func with(_ configure: (inout ImageRequest) -> Void) -> ImageRequest {
        var copy = self
        configure(&copy)
        return copy
    }
}

extension ImagePipeline {
    nonisolated func reconfigured(_ configure: (inout ImagePipeline.Configuration) -> Void) -> ImagePipeline {
        var configuration = self.configuration
        configure(&configuration)
        return ImagePipeline(configuration: configuration)
    }
}

extension ImageProcessing {
    /// A throwing version of a regular method.
    func processThrowing(_ image: PlatformImage) throws -> PlatformImage {
        let context = ImageProcessingContext(request: Test.request, response: Test.response, isCompleted: true)
        return (try process(ImageContainer(image: image), context: context)).image
    }
}

extension ImageCaching {
    subscript(request: ImageRequest) -> ImageContainer? {
        get { self[ImageCacheKey(request: request)] }
        set { self[ImageCacheKey(request: request)] = newValue }
    }
}

extension DataLoading {
    /// Test-only convenience that adapts the callback-based ``DataLoading`` API
    /// into an `AsyncThrowingStream` so tests can iterate chunks with
    /// `for try await`. Production code calls the callback API directly.
    func loadData(with request: URLRequest) -> AsyncThrowingStream<(Data, URLResponse), Error> {
        AsyncThrowingStream { continuation in
            let cancellable = self.loadData(
                with: request,
                didReceiveData: { data, response in
                    continuation.yield((data, response))
                },
                completion: { error in
                    continuation.finish(throwing: error)
                }
            )
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}

#if os(macOS)
import Cocoa
typealias _ImageView = NSImageView
#elseif os(iOS) || os(tvOS) || os(visionOS)
import UIKit
typealias _ImageView = UIImageView
#endif
