// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockImageCache: ImageCaching, @unchecked Sendable {
    private let lock = NSLock()
    var enabled = true
    var images = [AnyHashable: ImageContainer]()
    var readCount = 0
    var writeCount = 0

    init() {}

    func resetCounters() {
        readCount = 0
        writeCount = 0
    }

    subscript(key: ImageCacheKey) -> ImageContainer? {
        get {
            lock.withLock {
                readCount += 1
                return enabled ? images[key] : nil
            }
        }
        set {
            lock.withLock {
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
