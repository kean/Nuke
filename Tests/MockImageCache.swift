// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation
@testable import Nuke

class MockImageCache: ImageCaching {
    let queue = DispatchQueue(label: "com.github.Nuke.MockCache")
    var enabled = true
    var images = [AnyHashable: ImageResponse]()
    
    init() {}

    func cachedResponse(for request: ImageRequest) -> ImageResponse? {
        return queue.sync {
            enabled ? images[ImageRequest.CacheKey(request: request)] : nil
        }
    }

    func storeResponse(_ response: ImageResponse, for request: ImageRequest) {
        queue.sync {
            if enabled { images[ImageRequest.CacheKey(request: request)] = response }
        }
    }

    func removeResponse(for request: ImageRequest) {
        queue.sync {
            images[ImageRequest.CacheKey(request: request)] = nil
        }
    }
}
