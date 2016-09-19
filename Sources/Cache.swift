// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

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
    subscript(request: Request) -> Image? {
        get { return self[Request.cacheKey(for: request)] }
        set { self[Request.cacheKey(for: request)] = newValue }
    }
}

/// Auto-purging memory cache with LRU cleanup.
public final class Cache: Caching {
    // We don't use `NSCache` because it's not LRU
    
    private var map = [AnyHashable: Node<CachedImage>]()
    private var list = LinkedList<CachedImage>()
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Cache")

    /// The maximum total cost that the cache can hold.
    public var costLimit: Int { didSet { trim() } }
    
    /// The maximum number of items that the cache can hold.
    public var countLimit: Int { didSet { trim() } }
    
    /// The total cost of items in the cache.
    public private(set) var totalCost = 0
    
    /// The total number of items in the cache.
    public var totalCount: Int { return map.count }
    
    deinit {
        #if os(iOS) || os(tvOS)
            NotificationCenter.default.removeObserver(self)
        #endif
    }
    
    /// Initializes `Cache`.
    /// - parameter costLimit: Default value is calculated based on the amount
    /// of the available memory.
    public init(costLimit: Int = Cache.defaultCostLimit(), countLimit: Int = Int.max) {
        self.costLimit = costLimit
        self.countLimit = countLimit
        #if os(iOS) || os(tvOS)
            NotificationCenter.default.addObserver(self, selector: #selector(Cache.removeAll), name: .UIApplicationDidReceiveMemoryWarning, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(Cache.didEnterBackground), name: .UIApplicationDidEnterBackground, object: nil)
        #endif
    }
    
    private static func defaultCostLimit() -> Int {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let ratio = physicalMemory <= (1024 * 1024 * 512 /* 512 Mb */) ? 0.1 : 0.2
        let limit = physicalMemory / UInt64(1 / ratio)
        return limit > UInt64(Int.max) ? Int.max : Int(limit)
    }
    
    /// Accesses the image associated with the given key.
    public subscript(key: AnyHashable) -> Image? {
        get {
            return queue.sync {
                if let node = map[key] {
                    // bubble node up to the head
                    list.remove(node)
                    list.append(node)
                    return node.value.image
                }
                return nil
            }
        }
        set {
            queue.sync {
                if let image = newValue {
                    add(node: Node(value: CachedImage(image: image, cost: cost(image), key: key)))
                    trim()
                } else if let node = map[key] {
                    remove(node: node)
                }
            }
        }
    }
    
    private func add(node: Node<CachedImage>) {
        list.append(node)
        map[node.value.key] = node
        totalCost += node.value.cost
    }
    
    private func remove(node: Node<CachedImage>) {
        list.remove(node)
        map[node.value.key] = nil
        totalCost -= node.value.cost
    }
    
    /// Removes all cached images.
    public dynamic func removeAll() {
        queue.sync {
            map.removeAll()
            list.removeAll()
            totalCost = 0
        }
    }
    
    private func trim() {
        trim(toCost: costLimit)
        trim(toCount: countLimit)
    }
    
    private dynamic func didEnterBackground() {
        // Remove most of the stored items when entering background.
        // This behaviour is similar to `NSCache` (which removes all
        // items). This feature is not documented and may be subject
        // to change in future Nuke versions.
        trim(toCost: Int(Double(costLimit) * 0.1))
        trim(toCount: Int(Double(countLimit) * 0.1))
    }
    
    /// Removes least recently used items from the cache until the total cost
    /// of the remaining items is less than the given cost limit.
    public func trim(toCost limit: Int) {
        while totalCost > limit, let node = list.tail { // least recently used
            remove(node: node)
        }
    }
    
    /// Removes least recently used items from the cache until the total count
    /// of the remaining items is less than the given count limit.
    public func trim(toCount limit: Int) {
        while totalCount > limit, let node = list.tail { // least recently used
            remove(node: node)
        }
    }
    
    /// Returns cost for the given image by approximating its bitmap size in bytes in memory.
    public var cost: (Image) -> Int = {
        #if os(macOS)
            return 1
        #else
            guard let cgImage = $0.cgImage else { return 1 }
            return cgImage.bytesPerRow * cgImage.height
        #endif
    }
}

private struct CachedImage {
    var image: Image
    var cost: Int
    var key: AnyHashable
}

/// Basic doubly linked list.
private class LinkedList<V> {
    // head <-> node <-> ... <-> tail
    private(set) var head: Node<V>?
    private(set) var tail: Node<V>?
    
    /// Appends node to the head.
    func append(_ node: Node<V>) {
        if let currentHead = head {
            head = node
            currentHead.previous = node
            node.next = currentHead
        } else {
            head = node
            tail = node
        }
    }
    
    func remove(_ node: Node<V>) {
        node.next?.previous = node.previous // node.previous is nil if node=head
        node.previous?.next = node.next // node.next is nil if node=tail
        if node === head { head = node.next }
        if node === tail { tail = node.previous }
        node.next = nil
        node.previous = nil
    }
    
    func removeAll() {
        head = nil
        tail = nil
    }
}

private class Node<V> {
    let value: V
    var next: Node<V>?
    weak var previous: Node<V>?
    
    init(value: V) { self.value = value }
}
