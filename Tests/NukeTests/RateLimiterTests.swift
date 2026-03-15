// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

@Suite(.timeLimit(.minutes(1))) @ImagePipelineActor
struct RateLimiterTests {
    let rateLimiter = RateLimiter(rate: 10, burst: 2)

    @Test func burstIsExecutedImmediately() {
        var isExecuted = Array(repeating: false, count: 4)
        for i in isExecuted.indices {
            rateLimiter.execute {
                isExecuted[i] = true
                return true
            }
        }
        #expect(isExecuted == [true, true, false, false], "Expect first 2 items to be executed immediately")
    }

    @Test func posponedItemsDoNotExtractFromBucket() {
        var isExecuted = Array(repeating: false, count: 4)
        for i in isExecuted.indices {
            rateLimiter.execute {
                isExecuted[i] = true
                return i != 1 // important!
            }
        }
        #expect(isExecuted == [true, true, true, false], "Expect first 2 items to be executed immediately")
    }

    @Test(.disabled("Deadlocks on @ImagePipelineActor with withUnsafeContinuation — iOS 26.2")) func overflow() async {
        let count = 3
        await confirmation(expectedCount: count) { done in
            for _ in 0..<count {
                await withUnsafeContinuation { continuation in
                    rateLimiter.execute {
                        done()
                        continuation.resume(returning: ())
                        return true
                    }
                }
            }
        }
    }

    // MARK: - Edge Cases

    @Test func burstOfOneExecutesSingleItemImmediately() {
        // GIVEN - rate limiter that only allows 1 immediate execution
        let limiter = RateLimiter(rate: 10, burst: 1)
        var executed = [false, false]

        // WHEN
        limiter.execute { executed[0] = true; return true }
        limiter.execute { executed[1] = true; return true }

        // THEN - only the first item runs immediately; the second is deferred
        #expect(executed[0] == true)
        #expect(executed[1] == false)
    }

    @Test func allPostponedItemsDoNotDrainBucket() {
        // GIVEN - all items return false (none extract a token)
        let limiter = RateLimiter(rate: 10, burst: 2)
        var executed = [false, false, false, false, false]

        for i in executed.indices {
            limiter.execute {
                executed[i] = true
                return false // never consumes a token
            }
        }

        // THEN - burst allows the first 2 to run; subsequent items are queued
        // but since they all return false, earlier items' buckets refill and
        // the third item also executes (no token consumed)
        #expect(executed[0] == true)
        #expect(executed[1] == true)
        #expect(executed[2] == true)
    }
}
