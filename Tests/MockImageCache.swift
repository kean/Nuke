// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
@testable import Nuke

class MockImageCache: ImageCaching {
    let queue = DispatchQueue(label: "com.github.Nuke.MockCache")
    var enabled = true
    var images = [AnyHashable: ImageContainer]()
    
    init() {}

    subscript(key: ImageCacheKey) -> ImageContainer? {
        get {
            return queue.sync {
                enabled ? images[key] : nil
            }
        }
        set {
            queue.sync {
                if let image = newValue {
                    if enabled { images[key] = image }
                } else {
                    images[key] = nil
                }
            }
        }
    }
}
