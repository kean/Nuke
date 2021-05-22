// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
@testable import Nuke

class MockImageCache: ImageCaching {
    let queue = DispatchQueue(label: "com.github.Nuke.MockCache")
    var enabled = true
    var images = [AnyHashable: ImageContainer]()
    var readCount = 0
    var writeCount = 0

    init() {}

    subscript(key: ImageCacheKey) -> ImageContainer? {
        get {
            queue.sync {
                readCount += 1
                return enabled ? images[key] : nil
            }
        }
        set {
            queue.sync {
                writeCount += 1
                if let image = newValue {
                    if enabled { images[key] = image }
                } else {
                    images[key] = nil
                }
            }
        }
    }

    func removeAll() {
        images.removeAll()
    }
}
