// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

@propertyWrapper final class Atomic<T> {
    private var value: T
    private let lock: os_unfair_lock_t

    init(wrappedValue value: T) {
        self.value = value
        self.lock = .allocate(capacity: 1)
        self.lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    var wrappedValue: T {
        get { getValue() }
        set { setValue(newValue) }
    }

     private func getValue() -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return value
    }

    private func setValue(_ newValue: T) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        value = newValue
    }
}
