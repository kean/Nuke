// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockImageCache: ImageCaching, @unchecked Sendable {
    private let lock = NSLock()
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
                return _images[key]
            }
        }
        set {
            lock.withLock {
                _writeCount += 1
                _images[key] = newValue
            }
        }
    }

    func removeAll() {
        lock.withLock { _images.removeAll() }
    }
}
