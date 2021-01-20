// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A thread-safe value wrapper.
final class Atomic<T> {
    private var _value: T
    private let lock = NSLock()

    init(_ value: T) {
        self._value = value

        #if TRACK_ALLOCATIONS
        Allocations.increment("Atomic")
        #endif
    }

    deinit {
        #if TRACK_ALLOCATIONS
        Allocations.decrement("Atomic")
        #endif
    }

    var value: T {
        get {
            lock.lock()
            let value = _value
            lock.unlock()
            return value
        }
        set {
            lock.lock()
            _value = newValue
            lock.unlock()
        }
    }
}

extension Atomic where T: Equatable {
    /// "Compare and Swap"
    func swap(to newValue: T, ifEqual oldValue: T) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard _value == oldValue else {
            return false
        }
        _value = newValue
        return true
    }

    func map(_ transform: (T) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }

        _value = transform(_value)
        return _value
    }
}

extension Atomic where T == Int {
    /// Atomically increments the value and retruns a new incremented value.
    @discardableResult func increment() -> Int {
        map { $0 + 1 }
    }

    @discardableResult func decrement() -> Int {
        map { $0 - 1 }
    }
}
