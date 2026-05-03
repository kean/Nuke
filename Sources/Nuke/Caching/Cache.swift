// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit.UIApplication
#endif

// Internal memory-cache implementation.
final class Cache<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    // Can't use `NSCache` because it is not LRU

    struct Configuration {
        var costLimit: Int { didSet { recomputeEntryMaxCost() } }
        var countLimit: Int
        var ttl: TimeInterval?
        var entryCostLimit: Double { didSet { recomputeEntryMaxCost() } }
        private(set) var entryMaxCost: Int = .max

        init(costLimit: Int, countLimit: Int, ttl: TimeInterval?, entryCostLimit: Double) {
            self.costLimit = costLimit
            self.countLimit = countLimit
            self.ttl = ttl
            self.entryCostLimit = entryCostLimit
            recomputeEntryMaxCost()
        }

        private mutating func recomputeEntryMaxCost() {
            let clamped = max(0, min(entryCostLimit, 1))
            let product = clamped * Double(costLimit)
            entryMaxCost = product >= Double(Int.max) ? .max : Int(product)
        }
    }

    var conf: Configuration {
        get {
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            return _conf
        }
        set {
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            _conf = newValue
        }
    }

    private var _conf: Configuration {
        didSet { _trim() }
    }

    var totalCost: Int {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return _totalCost
    }

    var totalCount: Int {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return map.count
    }

    private var _totalCost = 0
    private var map = [Key: LinkedList<Entry>.Node]()
    private let list = LinkedList<Entry>()
    private let lock: os_unfair_lock_t
    private let memoryPressure: DispatchSourceMemoryPressure
    private var notificationObserver: AnyObject?

    init(costLimit: Int, countLimit: Int) {
        self._conf = Configuration(costLimit: costLimit, countLimit: countLimit, ttl: nil, entryCostLimit: 0.1)
        self.lock = .allocate(capacity: 1)
        self.lock.initialize(to: os_unfair_lock())

        self.memoryPressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        self.memoryPressure.setEventHandler { [weak self] in
            self?.removeAllCachedValues()
        }
        self.memoryPressure.resume()

#if os(iOS) || os(tvOS) || os(visionOS)
        Task {
            await registerForEnterBackground()
        }
#endif
    }

    deinit {
        memoryPressure.cancel()
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

#if os(iOS) || os(tvOS) || os(visionOS)
    @MainActor private func registerForEnterBackground() {
        notificationObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.clearCacheOnEnterBackground()
        }
    }
#endif

    func value(forKey key: Key) -> Value? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }

        guard let node = map[key] else {
            return nil
        }

        guard !node.value.isExpired else {
            _remove(node: node)
            return nil
        }

        // CLOCK / second-chance: mark as referenced instead of touching the
        // linked list. Shrinks the read critical section to a single store
        // so the unfair lock is held for less time under contention.
        if !node.value.referenced {
            node.value.referenced = true
        }

        return node.value.value
    }

    func set(_ value: Value, forKey key: Key, cost: Int = 0, ttl: TimeInterval? = nil) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }

        guard cost < _conf.entryMaxCost else {
            return
        }

        let ttl = ttl ?? _conf.ttl
        let expirationTimestamp = ttl.map { Date.timeIntervalSinceReferenceDate + $0 } ?? 0
        let entry = Entry(value: value, key: key, cost: cost, expirationTimestamp: expirationTimestamp)
        _add(entry)
        _trim()
    }

    @discardableResult
    func removeValue(forKey key: Key) -> Value? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }

        guard let node = map[key] else {
            return nil
        }
        _remove(node: node)
        return node.value.value
    }

    private func _add(_ element: Entry) {
        if let existingNode = map[element.key] {
            // Reuse the node to avoid a heap allocation on overwrite.
            _totalCost -= existingNode.value.cost
            existingNode.value = element
            // An update counts as a use; let CLOCK protect it on the next sweep.
            existingNode.value.referenced = true
        } else {
            map[element.key] = list.append(element)
        }
        _totalCost += element.cost
    }

    private func _remove(node: LinkedList<Entry>.Node) {
        list.remove(node)
        map[node.value.key] = nil
        _totalCost -= node.value.cost
    }

    func removeAllCachedValues() {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }

        map.removeAll()
        list.removeAllElements()
        _totalCost = 0
    }

    private func clearCacheOnEnterBackground() {
        // Remove most of the stored items when entering background.
        // This behavior is similar to `NSCache` (which removes all
        // items). This feature is not documented and may be subject
        // to change in future Nuke versions.
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }

        _trim(toCost: Int(Double(_conf.costLimit) * 0.1))
        _trim(toCount: Int(Double(_conf.countLimit) * 0.1))
    }

    private func _trim() {
        if _totalCost <= _conf.costLimit && map.count <= _conf.countLimit {
            return
        }
        _trim(toCost: _conf.costLimit)
        _trim(toCount: _conf.countLimit)
    }

    func trim(toCost limit: Int) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        _trim(toCost: limit)
    }

    private func _trim(toCost limit: Int) {
        _trim(while: { _totalCost > limit })
    }

    func trim(toCount limit: Int) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        _trim(toCount: limit)
    }

    private func _trim(toCount limit: Int) {
        _trim(while: { map.count > limit })
    }

    private func _trim(while condition: () -> Bool) {
        // CLOCK sweep: a referenced entry gets its bit cleared and moved to
        // the back (second chance); an unreferenced entry is evicted. Each
        // entry can survive at most one full pass before becoming a candidate.
        while condition(), let node = list.first {
            if node.value.referenced {
                node.value.referenced = false
                list.moveToLast(node)
            } else {
                _remove(node: node)
            }
        }
    }

    private struct Entry {
        let value: Value
        let key: Key
        let cost: Int
        // 0 means "never expires" — saves 8 bytes vs. `Date?` and avoids
        // the optional unwrap on every lookup.
        let expirationTimestamp: TimeInterval
        // CLOCK reference bit: set on read/update, cleared by the eviction sweep.
        var referenced: Bool = false
        var isExpired: Bool {
            expirationTimestamp != 0 && expirationTimestamp < Date.timeIntervalSinceReferenceDate
        }
    }
}
