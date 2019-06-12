// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

extension ImagePipeline.Error: Equatable {
    public static func == (lhs: ImagePipeline.Error, rhs: ImagePipeline.Error) -> Bool {
        switch (lhs, rhs) {
        case let (.dataLoadingFailed(lhs), .dataLoadingFailed(rhs)):
            return lhs as NSError == rhs as NSError
        case (.decodingFailed, .decodingFailed): return true
        case (.processingFailed, .processingFailed): return true
        default: return false
        }
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

extension ImageLoadingOptions {
    private static var stack = [ImageLoadingOptions]()

    static func pushShared(_ shared: ImageLoadingOptions) {
        stack.append(ImageLoadingOptions.shared)
        ImageLoadingOptions.shared = shared
    }

    static func popShared() {
        ImageLoadingOptions.shared = stack.removeLast()
    }
}

#if os(macOS)
import Cocoa
typealias _ImageView = NSImageView
#else
import UIKit
typealias _ImageView = UIImageView
#endif
