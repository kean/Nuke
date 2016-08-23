// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockCache: Caching {
    var enabled = true
    var images = [AnyHashable: Image]()
    init() {}

    func image(for key: AnyHashable) -> Image? {
        return enabled ? images[key] : nil
    }

    func setImage(_ image: Image, for key: AnyHashable) {
        if enabled {
            images[key] = image
        }
    }

    func removeImage(for key: AnyHashable) {
        if enabled {
            images[key] = nil
        }
    }
    
    func removeImage(for request: Request) {
        removeImage(for: Request.cacheKey(for: request))
    }
    
    func clear() {
        images.removeAll()
    }
}
