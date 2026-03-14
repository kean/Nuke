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
        case (.cancelled, .cancelled):
            return true
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

#if os(macOS)
import Cocoa
typealias _ImageView = NSImageView
#elseif os(iOS) || os(tvOS) || os(visionOS)
import UIKit
typealias _ImageView = UIImageView
#endif
