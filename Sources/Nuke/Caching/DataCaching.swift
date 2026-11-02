// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Data cache.
///
/// - important: The implementation must be thread safe.
public protocol DataCaching: Sendable {
    /// Retrieves data from cache for the given key.
    ///
    /// - note: The method is synchronous and is allowed to block: the pipeline
    /// never calls it on the main thread.
    func cachedData(for key: String) -> Data?

    /// Returns `true` if the cache contains data for the given key.
    ///
    /// - note: The method is synchronous and is allowed to block: the pipeline
    /// never calls it on the main thread.
    func containsData(for key: String) -> Bool

    /// Stores data for the given key.
    /// - note: The implementation must return immediately and store data
    /// asynchronously.
    func storeData(_ data: Data, for key: String)

    /// Stores data for the given key, with the given expiration. Read it with
    /// ``ImageRequest/CacheExpiration-swift.struct/expirationDate``. An entry
    /// that expired has to read as missing.
    ///
    /// The default implementation ignores the expiration and calls
    /// ``storeData(_:for:)``.
    ///
    /// - note: The implementation must return immediately and store data
    /// asynchronously.
    func storeData(_ data: Data, for key: String, expiration: ImageRequest.CacheExpiration)

    /// Returns the date the entry for the given key expires on, or `nil` if it
    /// doesn't expire. An image read from the entry stays in the memory cache
    /// no longer than that.
    ///
    /// The default implementation returns `nil`.
    ///
    /// - note: The method is synchronous and is allowed to block: the pipeline
    /// never calls it on the main thread.
    func expirationDate(for key: String) -> Date?

    /// Removes data for the given key.
    func removeData(for key: String)

    /// Removes all items.
    func removeAll()
}

extension DataCaching {
    public func storeData(_ data: Data, for key: String, expiration: ImageRequest.CacheExpiration) {
        storeData(data, for: key)
    }

    public func expirationDate(for key: String) -> Date? {
        nil
    }

    /// - parameter expiration: `nil` stores the data with none.
    func store(_ data: Data, for key: String, with expiration: ImageRequest.CacheExpiration?) {
        guard let expiration else {
            return storeData(data, for: key)
        }
        // A cache that doesn't implement expiration would keep this one for
        // good. The data still replaces what is stored for the key.
        guard expiration.timeToLive > 0 else {
            return removeData(for: key)
        }
        storeData(data, for: key, expiration: expiration)
    }
}
