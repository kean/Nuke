// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
#if os(macOS)
    import Cocoa
#else
    import UIKit
#endif

/// Provides in-memory storage for images.
///
/// The implementation is expected to be thread safe.
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

/// Auto-purging memory cache with LRU cleanup algorithm.
public final class Cache: Caching {
    // We don't use `NSCache` because it's not LRU
    
    private var map = [AnyHashable: Node<CachedImage>]()
    private var list = LinkedList<CachedImage>()
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Cache")
    
    public var capacity: Int { didSet { cleanup() } }
    private var usedCost = 0
    
    deinit {
        #if os(iOS) || os(tvOS)
            NotificationCenter.default.removeObserver(self)
        #endif
    }
    
    /// Initializes `Cache`.
    /// - parameter capacity: Default value is calculated based on the amount
    /// of available memory.
    public init(capacity: Int = Cache.defaultCapacity()) {
        self.capacity = capacity
        #if os(iOS) || os(tvOS)
            NotificationCenter.default.addObserver(self, selector: #selector(Cache.removeAll), name: .UIApplicationDidReceiveMemoryWarning, object: nil)
        #endif
    }
    
    private static func defaultCapacity() -> Int {
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
                    let node = Node(value: CachedImage(image: image, cost: cost(image), key: key))
                    map[key] = node
                    list.append(node)
                    
                    usedCost += node.value.cost
                    cleanup()
                } else {
                    if let node = map.removeValue(forKey: key) {
                        list.remove(node)
                    }
                }
            }
        }
    }
    
    /// Removes all cached images.
    public dynamic func removeAll() {
        queue.sync {
            map.removeAll()
            list.removeAll()
            usedCost = 0
        }
    }
    
    /// Removes images until the currently used cost is smaller than capacity.
    private func cleanup() {
        while usedCost > capacity, let node = list.tail { // least recently used
            list.remove(node)
            map[node.value.key] = nil
            usedCost -= node.value.cost
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
