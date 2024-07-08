// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

public final class MockDataCache: DataCaching, @unchecked Sendable {
    public var store = [String: Data]()
    public var readCount = 0
    public var writeCount = 0

    public init() {}

    public func resetCounters() {
        readCount = 0
        writeCount = 0
    }

    public func cachedData(for key: String) -> Data? {
        readCount += 1
        return store[key]
    }

    public func containsData(for key: String) -> Bool {
        store[key] != nil
    }

    public func storeData(_ data: Data, for key: String) {
        writeCount += 1
        store[key] = data
    }

    public func removeData(for key: String) {
        store[key] = nil
    }

    public func removeAll() {
        store.removeAll()
    }
}
