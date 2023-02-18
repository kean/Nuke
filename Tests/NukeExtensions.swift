// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

extension ImagePipeline.Error: Equatable {
    public static func == (lhs: ImagePipeline.Error, rhs: ImagePipeline.Error) -> Bool {
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
        default: return false
        }
    }
}

extension ImageResponse: Equatable {
    public static func == (lhs: ImageResponse, rhs: ImageResponse) -> Bool {
        return lhs.image === rhs.image
    }
}

extension ImagePipeline {
    func reconfigured(_ configure: (inout ImagePipeline.Configuration) -> Void) -> ImagePipeline {
        var configuration = self.configuration
        configure(&configuration)
        return ImagePipeline(configuration: configuration)
    }
}

extension ImagePipeline {
    private static var stack = [ImagePipeline]()

    static func pushShared(_ shared: ImagePipeline) {
        stack.append(ImagePipeline.shared)
        ImagePipeline.shared = shared
    }

    static func popShared() {
        ImagePipeline.shared = stack.removeLast()
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
#elseif os(iOS) || os(tvOS)
import UIKit
typealias _ImageView = UIImageView
#endif
