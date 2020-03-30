// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

import Foundation
@testable import Nuke

class MockImageCache: ImageCaching {
    let queue = DispatchQueue(label: "com.github.Nuke.MockCache")
    var enabled = true
    var images = [AnyHashable: ImageContainer]()
    
    init() {}

    subscript(request: ImageRequest) -> ImageContainer? {
        get {
            return queue.sync {
                enabled ? images[ImageRequest.CacheKey(request: request)] : nil
            }
        }
        set {
            queue.sync {
                if let image = newValue {
                    if enabled { images[ImageRequest.CacheKey(request: request)] = image }
                } else {
                    images[ImageRequest.CacheKey(request: request)] = nil
                }
            }
        }
    }
}
