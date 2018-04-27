// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockImageCache: ImageCaching {
    let queue = DispatchQueue(label: "com.github.Nuke.MockCache")
    var enabled = true
    var images = [AnyHashable: ImageResponse]()
    
    init() {}

    func cachedResponse(for request: ImageRequest) -> ImageResponse? {
        return queue.sync {
            enabled ? images[request.cacheKey] : nil
        }
    }

    func storeResponse(_ response: ImageResponse, for request: ImageRequest) {
        queue.sync {
            if enabled { images[request.cacheKey] = response }
        }
    }

    func removeResponse(for request: ImageRequest) {
        queue.sync {
            images[request.cacheKey] = nil
        }
    }
}
