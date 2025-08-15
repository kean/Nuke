// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

final class Mutex<T>: @unchecked Sendable {
    private var _value: T
    private let lock: os_unfair_lock_t

    init(_ value: T) {
        self._value = value
        self.lock = .allocate(capacity: 1)
        self.lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    var value: T {
        get {
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            return _value
        }
        set {
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            _value = newValue
        }
    }

    func withLock<U>(_ closure: (inout T) -> U) -> U {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return closure(&_value)
    }
}

extension Mutex where T: Equatable {
    /// Sets the value to the given value and `returns` true` if
    /// the value changed.
    func setValue(_ newValue: T) -> Bool {
        withLock {
            guard $0 != newValue else { return false }
            $0 = newValue
            return true
        }
    }
}

extension Mutex where T: BinaryInteger {
    func incremented() -> T {
        withLock {
            let value = $0
            $0 += 1
            return value
        }
    }
}
