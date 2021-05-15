// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

final class MockDataCache: DataCaching {
    var store = [String: Data]()
    var readCount = 0
    var writeCount = 0

    func cachedData(for key: String) -> Data? {
        readCount += 1
        return store[key]
    }

    func containsData(for key: String) -> Bool {
        store[key] != nil
    }

    func storeData(_ data: Data, for key: String) {
        writeCount += 1
        store[key] = data
    }

    func removeData(for key: String) {
        store[key] = nil
    }

    func removeAll() {
        store.removeAll()
    }
}
