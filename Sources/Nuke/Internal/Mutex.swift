// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

final class Mutex<T>: @unchecked Sendable {
    private var _value: T
    private let lock: os_unfair_lock_t

    init(value: T) {
        self._value = value
        self.lock = .allocate(capacity: 1)
        self.lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    var value: T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return _value
    }

    /// Replaces the value, and releases the old one after unlocking: its
    /// `deinit` can run any code, including code that reads this mutex.
    func replace(with newValue: T) {
        let oldValue = withLock { (value: inout T) -> T in
            let oldValue = value
            value = newValue
            return oldValue
        }
        withExtendedLifetime(oldValue) {}
    }

    func withLock<U>(_ closure: (inout T) -> U) -> U {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return closure(&_value)
    }
}

extension Mutex where T: Equatable {
    /// Atomically sets the value if it differs from the current one.
    /// Returns `true` if the value was changed.
    @discardableResult
    func testAndSet(_ newValue: T) -> Bool {
        withLock {
            guard $0 != newValue else { return false }
            $0 = newValue
            return true
        }
    }
}
