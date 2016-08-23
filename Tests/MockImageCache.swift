// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockCache: Caching {
    var enabled = true
    var images = [AnyHashable: Image]()
    init() {}

    subscript(key: AnyHashable) -> Image? {
        get { return enabled ? images[key] : nil }
        set { if enabled { images[key] = newValue } }
    }
}
