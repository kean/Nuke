// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockCache: Caching {
    let queue = DispatchQueue(label: "com.github.Nuke.MockCache")
    var enabled = true
    var images = [AnyHashable: Image]()
    
    init() {}

    subscript(key: AnyHashable) -> Image? {
        get {
            return queue.sync {
                enabled ? images[key] : nil
            }
        }
        set {
            queue.sync {
                if enabled { images[key] = newValue }
            }
        }
    }
}
