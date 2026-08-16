// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

final class Mutex<T>: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<T>

    init(value: T) {
        self.lock = OSAllocatedUnfairLock(uncheckedState: value)
    }

    var value: T {
        lock.withLockUnchecked { $0 }
    }

    func withLock<U>(_ closure: (inout T) -> U) -> U {
        lock.withLockUnchecked(closure)
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
