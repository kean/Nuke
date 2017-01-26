// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

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
