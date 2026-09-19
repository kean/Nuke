// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

// SUSPECTED BUG (race): concurrent writes to different `ImageCache`
// configuration properties overwrite each other.
//
// Each setter – `costLimit`, `countLimit`, `ttl`, `entryCostLimit`
// (Sources/Nuke/Caching/ImageCache.swift:26-50) – is `impl.conf.x = newValue`,
// which Swift performs as a read-modify-write of the whole `Configuration`
// through `Cache.conf`'s separate `get` and `set` (Cache.swift:38-49). Each of
// the two takes the lock, but the lock is released in between, so a write of
// `countLimit` on one thread that reads `conf` before, and writes it back
// after, a write of `costLimit` on another thread puts the old `costLimit`
// back.
//
// `ImageCaching` requires "The implementation must be thread safe", and
// `ImageCache` has no other way to change its limits.
//
// Expected: a thread that is the only writer of `costLimit` reads back the
// value it just wrote.
// Actual: another thread's `countLimit` write reverts it (lost updates are
// counted below: 10 810 of 200 000 reads in one run on an M-series Mac).
@Suite(.timeLimit(.minutes(5)))
struct MemoryCacheConfigRaceRepro {
    @Test func concurrentLimitWritesAreNotLost() {
        // Given
        let cache = ImageCache(costLimit: 0, countLimit: 0)
        let lostUpdates = OSAllocatedUnfairLock(initialState: 0)
        let iterations = 100_000

        // When one thread only writes `costLimit` and another only writes `countLimit`
        DispatchQueue.concurrentPerform(iterations: 2) { worker in
            for value in 1...iterations {
                if worker == 0 {
                    cache.costLimit = value
                    if cache.costLimit != value { lostUpdates.withLock { $0 += 1 } }
                } else {
                    cache.countLimit = value
                    if cache.countLimit != value { lostUpdates.withLock { $0 += 1 } }
                }
            }
        }

        // Then neither thread ever loses its own write
        #expect(lostUpdates.withLock { $0 } == 0) // fails
    }
}
