// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Counts events, such as `didComplete` calls, and lets the test wait for the
/// n-th one.
final class EventCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    private var waiters: [(count: Int, expectation: TestExpectation)] = []

    var count: Int { lock.withLock { _count } }

    func increment() {
        let ready = lock.withLock {
            _count += 1
            let ready = waiters.filter { $0.count <= _count }
            waiters.removeAll { $0.count <= _count }
            return ready
        }
        for waiter in ready {
            waiter.expectation.fulfill()
        }
    }

    /// Waits until the count reaches the given one, or records an issue if it
    /// doesn't in time, like ``TestExpectation/wait(timeout:)``.
    func wait(for count: Int) async {
        let expectation = TestExpectation()
        let isReached = lock.withLock {
            guard _count < count else { return true }
            waiters.append((count, expectation))
            return false
        }
        if !isReached {
            await expectation.wait()
        }
    }
}
