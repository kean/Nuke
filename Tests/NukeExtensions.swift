// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

extension ImageRequest {
    func mutated(_ closure: (inout ImageRequest) -> Void) -> ImageRequest {
        var request = self
        closure(&request)
        return request
    }

    func with(processorId: String) -> ImageRequest {
        return processed(with: MockImageProcessor(id: processorId))
    }

    func with(priority: Priority) -> ImageRequest {
        var request = self
        request.priority = priority
        return request
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
