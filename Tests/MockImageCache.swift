// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockCache: Caching {
    var enabled = true
    var images = [URL: Image]()
    init() {}

    func image(for request: Request) -> Image? {
        return enabled ? images[request.urlRequest.url!] : nil
    }
    
    func setImage(_ image: Image, for request: Request) {
        if enabled {
            images[request.urlRequest.url!] = image
        }
    }
    
    func removeImage(for request: Request) {
        if enabled {
            images[request.urlRequest.url!] = nil
        }
    }
    
    func clear() {
        images.removeAll()
    }
}
