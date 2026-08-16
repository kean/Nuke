// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import os

/// A mutual exclusion lock that guards a value.
///
/// Backed by `OSAllocatedUnfairLock`, which owns the lock's storage. An
/// `os_unfair_lock` must never be copied or moved, and storing one in a Swift
/// property gives the compiler license to do exactly that, which aborts the
/// process with `_os_unfair_lock_corruption_abort` – https://github.com/kean/Nuke/issues/841.
///
/// The value is constrained to `Sendable` to keep the critical section from
/// handing out state that isn't safe to use outside it. That's the same
/// discipline the standard library's `Synchronization.Mutex` enforces, which
/// this type can be swapped for once the deployment target reaches iOS 18.
struct Mutex<T: Sendable>: Sendable {
    private let lock: OSAllocatedUnfairLock<T>

    init(value: T) {
        lock = OSAllocatedUnfairLock(initialState: value)
    }

    var value: T {
        lock.withLockUnchecked { $0 }
    }

    /// Calls the closure with exclusive access to the value.
    ///
    /// - warning: The closure must never call back into anything that acquires
    /// the same lock: `os_unfair_lock` is not recursive and re-entering it
    /// traps.
    func withLock<U>(_ closure: (inout T) throws -> U) rethrows -> U {
        // `withLockUnchecked` rather than `withLock`: the latter requires a
        // `@Sendable` closure and a `Sendable` result, which the call sites
        // don't need. The closure is scoped and synchronous, and `T` is already
        // `Sendable`.
        try lock.withLockUnchecked(closure)
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
