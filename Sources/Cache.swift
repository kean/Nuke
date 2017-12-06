// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation
#if os(macOS)
    import Cocoa
#else
    import UIKit
#endif

/// In-memory image cache.
///
/// The implementation must be thread safe.
public protocol Caching: class {
    /// Accesses the image associated with the given key.
    subscript(key: AnyHashable) -> Image? { get set }
}

public extension Caching {
    /// Accesses the image associated with the given request.
    public subscript(request: Request) -> Image? {
        get { return self[Request.cacheKey(for: request)] }
        set { self[Request.cacheKey(for: request)] = newValue }
    }
}

/// Memory cache with LRU cleanup policy (least recently used are removed first).
///
/// The elements stored in cache are automatically discarded if either *cost* or
/// *count* limit is reached. The default cost limit represents a number of bytes
/// and is calculated based on the amount of physical memory available on the
/// device. The default count limit is set to `Int.max`.
///
/// `Cache` automatically removes all stored elements when it received a
/// memory warning. It also automatically removes *most* of cached elements
/// when the app enters background.
public final class Cache: Caching {
    // We don't use `NSCache` because it's not LRU

    private var map = [AnyHashable: LinkedList<CachedImage>.Node]()
    private let list = LinkedList<CachedImage>()
    private let lock = Lock()

    /// The maximum total cost that the cache can hold.
    public var costLimit: Int { didSet { lock.sync { _trim() } } }

    /// The maximum number of items that the cache can hold.
    public var countLimit: Int { didSet { lock.sync { _trim() } } }

    /// The total cost of items in the cache.
    public private(set) var totalCost = 0

    /// The total number of items in the cache.
    public var totalCount: Int { return map.count }

    /// Shared `Cache` instance.
    public static let shared = Cache()

    /// Initializes `Cache`.
    /// - parameter costLimit: Default value representes a number of bytes and is
    /// calculated based on the amount of the phisical memory available on the device.
    /// - parameter countLimit: `Int.max` by default.
    public init(costLimit: Int = Cache.defaultCostLimit(), countLimit: Int = Int.max) {
        self.costLimit = costLimit
        self.countLimit = countLimit
        #if os(iOS) || os(tvOS)
            NotificationCenter.default.addObserver(self, selector: #selector(removeAll), name: .UIApplicationDidReceiveMemoryWarning, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground), name: .UIApplicationDidEnterBackground, object: nil)
        #endif
    }

    deinit {
        #if os(iOS) || os(tvOS)
            NotificationCenter.default.removeObserver(self)
        #endif
    }

    /// Returns a recommended cost limit which is computed based on the amount
    /// of the phisical memory available on the device.
    public static func defaultCostLimit() -> Int {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let ratio = physicalMemory <= (1024 * 1024 * 512 /* 512 Mb */) ? 0.1 : 0.2
        let limit = physicalMemory / UInt64(1 / ratio)
        return limit > UInt64(Int.max) ? Int.max : Int(limit)
    }

    /// Accesses the image associated with the given key.
    public subscript(key: AnyHashable) -> Image? {
        get {
            lock.lock()  // slightly aster than `sync()`
            defer { lock.unlock() }

            guard let node = map[key] else { return nil }

            // bubble node up to the head
            list.remove(node)
            list.append(node)

            return node.value.image
        }
        set {
            lock.lock() // slightly faster than `sync()`
            defer { lock.unlock() }

            if let image = newValue {
                let value = CachedImage(image: image, cost: cost(image), key: key)
                _add(node: LinkedList.Node(value: value))
                _trim() // _trim is extremely fast, it's OK to call it each time
            } else {
                guard let node = map[key] else { return }
                _remove(node: node)
            }
        }
    }

    private func _add(node: LinkedList<CachedImage>.Node) {
        if let existingNode = map[node.value.key] {
            _remove(node: existingNode)
        }
        list.append(node)
        map[node.value.key] = node
        totalCost += node.value.cost
    }

    private func _remove(node: LinkedList<CachedImage>.Node) {
        list.remove(node)
        map[node.value.key] = nil
        totalCost -= node.value.cost
    }

    /// Removes all cached images.
    @objc public dynamic func removeAll() {
        lock.sync {
            map.removeAll()
            list.removeAll()
            totalCost = 0
        }
    }

    private func _trim() {
        _trim(toCost: costLimit)
        _trim(toCount: countLimit)
    }

    @objc private dynamic func didEnterBackground() {
        // Remove most of the stored items when entering background.
        // This behavior is similar to `NSCache` (which removes all
        // items). This feature is not documented and may be subject
        // to change in future Nuke versions.
        lock.sync {
            _trim(toCost: Int(Double(costLimit) * 0.1))
            _trim(toCount: Int(Double(countLimit) * 0.1))
        }
    }

    /// Removes least recently used items from the cache until the total cost
    /// of the remaining items is less than the given cost limit.
    public func trim(toCost limit: Int) {
        lock.sync { _trim(toCost: limit) }
    }

    private func _trim(toCost limit: Int) {
        _trim(while: { totalCost > limit })
    }

    /// Removes least recently used items from the cache until the total count
    /// of the remaining items is less than the given count limit.
    public func trim(toCount limit: Int) {
        lock.sync { _trim(toCount: limit) }
    }

    private func _trim(toCount limit: Int) {
        _trim(while: { totalCount > limit })
    }

    private func _trim(while condition: () -> Bool) {
        while condition(), let node = list.tail { // least recently used
            _remove(node: node)
        }
    }

    /// Returns cost for the given image by approximating its bitmap size in bytes in memory.
    public var cost: (Image) -> Int = {
        #if os(macOS)
            return 1
        #else
            // bytesPerRow * height gives a rough estimation of how much memory
            // image uses in bytes. In practice this algorithm combined with a 
            // concervative default cost limit works OK.
            guard let cgImage = $0.cgImage else { return 1 }
            return cgImage.bytesPerRow * cgImage.height
        #endif
    }
}

private struct CachedImage {
    let image: Image
    let cost: Int
    let key: AnyHashable
}
