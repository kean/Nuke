// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct MutexTests {
    @Test func valueReturnsTheInitialValue() {
        let mutex = Nuke.Mutex(value: 7)

        #expect(mutex.value == 7)
    }

    @Test func withLockMutatesTheValueInPlace() {
        let mutex = Nuke.Mutex(value: 7)

        mutex.withLock { $0 += 1 }

        #expect(mutex.value == 8)
    }

    @Test func withLockReturnsTheClosureResult() {
        let mutex = Nuke.Mutex(value: "a")

        let previous = mutex.withLock { value -> String in
            let previous = value
            value = "b"
            return previous
        }

        #expect(previous == "a")
        #expect(mutex.value == "b")
    }

    @Test func withLockRethrowsTheClosureError() {
        struct Failure: Error {}
        let mutex = Nuke.Mutex(value: 0)

        #expect(throws: Failure.self) {
            try mutex.withLock { _ in throw Failure() }
        }

        // The lock is released, so it can still be acquired.
        mutex.withLock { $0 = 1 }
        #expect(mutex.value == 1)
    }

    @Test func testAndSetChangesTheValueWhenItDiffers() {
        let mutex = Nuke.Mutex(value: 1)

        #expect(mutex.testAndSet(2) == true)
        #expect(mutex.value == 2)
    }

    @Test func testAndSetDoesNothingWhenTheValueMatches() {
        let mutex = Nuke.Mutex(value: 1)

        #expect(mutex.testAndSet(1) == false)
        #expect(mutex.value == 1)
    }

    /// A copy shares the storage with the original: the lock and the value it
    /// guards live in the allocation owned by `OSAllocatedUnfairLock`, not in
    /// the `Mutex` value itself.
    @Test func copiesShareTheUnderlyingStorage() {
        let mutex = Nuke.Mutex(value: 0)
        let copy = mutex

        copy.withLock { $0 = 42 }

        #expect(mutex.value == 42)
    }

    /// Regression coverage for https://github.com/kean/Nuke/issues/841: an
    /// `os_unfair_lock` stored inline in a Swift value can be copied by the
    /// compiler, and locking a copy aborts the process. Passing the mutex
    /// across concurrent tasks is exactly the shape that used to trip it.
    @Test func concurrentIncrementsDoNotLoseUpdates() async {
        let iterations = 1_000
        let mutex = Nuke.Mutex(value: 0)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    mutex.withLock { $0 += 1 }
                }
            }
        }

        #expect(mutex.value == iterations)
    }

    @Test func concurrentTestAndSetReportsExactlyOneChange() async {
        let mutex = Nuke.Mutex(value: 0)

        let changes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<1_000 {
                group.addTask { mutex.testAndSet(1) }
            }
            return await group.reduce(into: 0) { $0 += $1 ? 1 : 0 }
        }

        #expect(changes == 1)
        #expect(mutex.value == 1)
    }
}
