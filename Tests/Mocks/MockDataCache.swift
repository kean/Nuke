// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

final class MockDataCache: DataCaching, @unchecked Sendable {
    var store: [String: Data] {
        get { lock.withLock { _store } }
        set { lock.withLock { _store = newValue } }
    }
    var readCount: Int { lock.withLock { _readCount } }
    var writeCount: Int { lock.withLock { _writeCount } }

    // The pipeline reads and writes from its own threads, and the test reads
    // what it did from another.
    private let lock = NSLock()
    private var _store = [String: Data]()
    private var _readCount = 0
    private var _writeCount = 0

    func resetCounters() {
        lock.withLock {
            _readCount = 0
            _writeCount = 0
        }
    }

    func cachedData(for key: String) -> Data? {
        lock.withLock {
            _readCount += 1
            return _store[key]
        }
    }

    func containsData(for key: String) -> Bool {
        lock.withLock { _store[key] != nil }
    }

    func storeData(_ data: Data, for key: String) {
        lock.withLock {
            _writeCount += 1
            _store[key] = data
        }
    }

    func removeData(for key: String) {
        lock.withLock { _store[key] = nil }
    }

    func removeAll() {
        lock.withLock { _store.removeAll() }
    }
}
