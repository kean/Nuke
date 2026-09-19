// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

@testable import Nuke
import Testing
import Foundation

// SUSPECTED BUG: `ImageCache` configuration setters lose concurrent updates.
//
// `ImageCache.costLimit` (and `countLimit`, `ttl`, `entryCostLimit`) is
// implemented as `impl.conf.costLimit = newValue`, where `Cache.conf` is a
// computed property with a locked getter and a locked setter. Swift performs
// the nested assignment as read-modify-write: it takes the lock to *copy* the
// whole `Configuration`, releases it, mutates the copy, and takes the lock
// again to write the copy back. Two threads changing two *different* limits
// at the same time can therefore overwrite each other's change with the stale
// value they copied.
//
// Expected: after two threads finish setting `costLimit` and `countLimit`
// concurrently, each limit holds the last value its thread set (`ImageCaching`
// documents that "the implementation must be thread safe").
// Actual: in roughly half of the rounds one of the limits reverts to an older
// value (e.g. `costLimit` ends at 2150 instead of 2199), and the cache then
// trims to – or fails to trim to – a limit nobody set last.
//
// Location: Sources/Nuke/Caching/ImageCache.swift:26-50 (the setters), with
// Sources/Nuke/Caching/Cache.swift:36-47 (`conf` get/set) as the root cause.
@Suite(.timeLimit(.minutes(5)))
struct ImageCacheConfigurationLostUpdateRepro {
    @Test func concurrentLimitChangesAreNotLost() {
        var roundsWithLostUpdate = 0
        for _ in 0..<500 {
            let cache = ImageCache(costLimit: 1000, countLimit: 1000)
            DispatchQueue.concurrentPerform(iterations: 2) { index in
                if index == 0 {
                    for value in 0..<200 { cache.costLimit = 2000 + value }
                } else {
                    for value in 0..<200 { cache.countLimit = 3000 + value }
                }
            }
            if cache.costLimit != 2199 || cache.countLimit != 3199 {
                roundsWithLostUpdate += 1
            }
        }
        #expect(roundsWithLostUpdate == 0)
    }
}
