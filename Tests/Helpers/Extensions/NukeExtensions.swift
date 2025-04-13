// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

extension ImageTask.Error: @retroactive Equatable {
    public static func == (lhs: ImageTask.Error, rhs: ImageTask.Error) -> Bool {
        switch (lhs, rhs) {
        case (.dataMissingInCache, .dataMissingInCache): return true
        case let (.dataLoadingFailed(lhs), .dataLoadingFailed(rhs)):
            return lhs as NSError == rhs as NSError
        case (.dataIsEmpty, .dataIsEmpty): return true
        case (.decoderNotRegistered, .decoderNotRegistered): return true
        case (.decodingFailed, .decodingFailed): return true
        case (.processingFailed, .processingFailed): return true
        case (.imageRequestMissing, .imageRequestMissing): return true
        case (.pipelineInvalidated, .pipelineInvalidated): return true
        case (.cancelled, .cancelled): return true
        default: return false
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
