// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
#if !os(macOS)
import UIKit
#else
import Cocoa
#endif

/// An LRU memory cache.
///
/// The elements stored in cache are automatically discarded if either *cost* or
/// *count* limit is reached. The default cost limit represents a number of bytes
/// and is calculated based on the amount of physical memory available on the
/// device. The default count limit is set to `Int.max`.
///
/// ``ImageCache`` automatically removes all stored elements when it receives a
/// memory warning. It also automatically removes *most* stored elements
/// when the app enters the background.
public final class ImageCache: ImageCaching {
    private let impl: Cache<ImageCacheKey, ImageContainer>

    /// The maximum total cost that the cache can hold.
    public var costLimit: Int {
        get { impl.conf.costLimit }
        set { impl.conf.costLimit = newValue }
    }

    /// The maximum number of items that the cache can hold.
    public var countLimit: Int {
        get { impl.conf.countLimit }
        set { impl.conf.countLimit = newValue }
    }

    /// Default TTL (time to live) for each entry. Can be used to make sure that
    /// the entries get validated at some point. `nil` (never expire) by default.
    public var ttl: TimeInterval? {
        get { impl.conf.ttl }
        set { impl.conf.ttl = newValue }
    }

    /// The maximum cost of an entry in proportion to the ``costLimit``.
    /// By default, `0.1`.
    public var entryCostLimit: Double {
        get { impl.conf.entryCostLimit }
        set { impl.conf.entryCostLimit = newValue }
    }

    /// The total number of items in the cache.
    public var totalCount: Int { impl.totalCount }

    /// The total cost of items in the cache.
    public var totalCost: Int { impl.totalCost }

    /// Shared `Cache` instance.
    public static let shared = ImageCache()

    deinit {
        #if TRACK_ALLOCATIONS
        Allocations.decrement("ImageCache")
        #endif
    }

    /// Initializes `Cache`.
    /// - parameter costLimit: Default value representes a number of bytes and is
    /// calculated based on the amount of the phisical memory available on the device.
    /// - parameter countLimit: `Int.max` by default.
    public init(costLimit: Int = ImageCache.defaultCostLimit(), countLimit: Int = Int.max) {
        impl = Cache(costLimit: costLimit, countLimit: countLimit)

        #if TRACK_ALLOCATIONS
        Allocations.increment("ImageCache")
        #endif
    }

    /// Returns a recommended cost limit which is computed based on the amount
    /// of the phisical memory available on the device.
    public static func defaultCostLimit() -> Int {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let ratio = physicalMemory <= (536_870_912 /* 512 Mb */) ? 0.1 : 0.2
        let limit = physicalMemory / UInt64(1 / ratio)
        return limit > UInt64(Int.max) ? Int.max : Int(limit)
    }

    public subscript(key: ImageCacheKey) -> ImageContainer? {
        get { impl.value(forKey: key) }
        set {
            if let image = newValue {
                impl.set(image, forKey: key, cost: cost(for: image))
            } else {
                impl.removeValue(forKey: key)
            }
        }
    }

    /// Removes all cached images.
    public func removeAll() {
        impl.removeAll()
    }
    /// Removes least recently used items from the cache until the total cost
    /// of the remaining items is less than the given cost limit.
    public func trim(toCost limit: Int) {
        impl.trim(toCost: limit)
    }

    /// Removes least recently used items from the cache until the total count
    /// of the remaining items is less than the given count limit.
    public func trim(toCount limit: Int) {
        impl.trim(toCount: limit)
    }

    /// Returns cost for the given image by approximating its bitmap size in bytes in memory.
    func cost(for container: ImageContainer) -> Int {
        let dataCost = container.data?.count ?? 0

        // bytesPerRow * height gives a rough estimation of how much memory
        // image uses in bytes. In practice this algorithm combined with a
        // conservative default cost limit works OK.
        guard let cgImage = container.image.cgImage else {
            return 1 + dataCost
        }
        return cgImage.bytesPerRow * cgImage.height + dataCost
    }
}
