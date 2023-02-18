// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Data cache.
///
/// - important: The implementation must be thread safe.
public protocol DataCaching: Sendable {
    /// Retrieves data from cache for the given key.
    func cachedData(for key: String) -> Data?

    /// Returns `true` if the cache contains data for the given key.
    func containsData(for key: String) -> Bool

    /// Stores data for the given key.
    /// - note: The implementation must return immediately and store data
    /// asynchronously.
    func storeData(_ data: Data, for key: String)

    /// Removes data for the given key.
    func removeData(for key: String)

    /// Removes all items.
    func removeAll()
}
