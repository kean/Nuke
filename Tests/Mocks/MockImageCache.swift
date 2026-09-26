// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockImageCache: ImageCaching, @unchecked Sendable {
    private let lock = NSLock()
    var enabled = true
    var images: [AnyHashable: ImageContainer] { lock.withLock { _images } }
    var readCount: Int { lock.withLock { _readCount } }
    var writeCount: Int { lock.withLock { _writeCount } }

    private var _images = [AnyHashable: ImageContainer]()
    private var _readCount = 0
    private var _writeCount = 0

    init() {}

    func resetCounters() {
        lock.withLock {
            _readCount = 0
            _writeCount = 0
        }
    }

    subscript(key: ImageCacheKey) -> ImageContainer? {
        get {
            lock.withLock {
                _readCount += 1
                return enabled ? _images[key] : nil
            }
        }
        set {
            lock.withLock {
                _writeCount += 1
                if let image = newValue {
                    if enabled { _images[key] = image }
                } else {
                    _images[key] = nil
                }
            }
        }
    }

    func removeAll() {
        lock.withLock { _images.removeAll() }
    }
}
