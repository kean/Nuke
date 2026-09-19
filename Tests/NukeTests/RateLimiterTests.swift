// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5))) @ImagePipelineActor
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

    @Test func overflow() async {
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

@Suite(.timeLimit(.minutes(5))) @ImagePipelineActor
struct RateLimiterSchedulingTests {
    @Test func deferredWorkRunsInTheOrderItWasSubmitted() async {
        // GIVEN a limiter that only lets the first item through right away
        let rateLimiter = RateLimiter(rate: 100, burst: 1)
        var order: [Int] = []
        let done = TestExpectation()

        // WHEN
        for i in 0..<5 {
            rateLimiter.execute {
                order.append(i)
                if i == 4 { done.fulfill() }
                return true
            }
        }
        #expect(order == [0])
        await done.wait()

        // THEN
        #expect(order == [0, 1, 2, 3, 4])
    }

    /// Work submitted while there is deferred work waits behind it, even when
    /// it is submitted by the deferred work itself.
    @Test func workSubmittedFromDeferredWorkRunsAfterTheWorkAlreadyWaiting() async {
        // GIVEN
        let rateLimiter = RateLimiter(rate: 100, burst: 1)
        var order: [Int] = []
        let done = TestExpectation()

        // WHEN
        rateLimiter.execute { order.append(0); return true }
        rateLimiter.execute {
            order.append(1)
            rateLimiter.execute {
                order.append(4)
                done.fulfill()
                return true
            }
            return true
        }
        rateLimiter.execute { order.append(2); return true }
        rateLimiter.execute { order.append(3); return true }
        await done.wait()

        // THEN
        #expect(order == [0, 1, 2, 3, 4])
    }

    @Test func tokensRefillAtTheConfiguredRate() async throws {
        // GIVEN a limiter that refills a token every 200 ms
        let rateLimiter = RateLimiter(rate: 5, burst: 1)
        var timestamps: [CFAbsoluteTime] = []
        let done = TestExpectation()

        // WHEN
        for i in 0..<3 {
            rateLimiter.execute {
                timestamps.append(CFAbsoluteTimeGetCurrent())
                if i == 2 { done.fulfill() }
                return true
            }
        }
        await done.wait()

        // THEN each deferred item waits for a token of its own. Only the lower
        // bounds are checked: a busy machine can only make the work run later.
        try #require(timestamps.count == 3)
        #expect(timestamps[1] - timestamps[0] >= 0.19)
        #expect(timestamps[2] - timestamps[0] >= 0.39)
    }

    @Test func deferredWorkThatWasCancelledDoesNotUseUpAToken() async {
        // GIVEN a limiter with no tokens left
        let rateLimiter = RateLimiter(rate: 10, burst: 1)
        rateLimiter.execute { true }
        let isInTheSamePass = Ref(false)
        var wasRunInTheSamePass: Bool?
        let done = TestExpectation()

        // WHEN the first deferred item turns out to be cancelled
        rateLimiter.execute {
            // The limiter runs deferred work in a single pass on the actor, so
            // the hop to reset the flag can only run after the pass is over.
            isInTheSamePass.value = true
            Task { @ImagePipelineActor in isInTheSamePass.value = false }
            return false
        }
        rateLimiter.execute {
            wasRunInTheSamePass = isInTheSamePass.value
            done.fulfill()
            return true
        }
        await done.wait()

        // THEN the token it didn't use goes to the next item right away
        #expect(wasRunInTheSamePass == true)
    }

    @Test func tokensDoNotAccumulateBeyondTheBurst() async throws {
        // GIVEN a limiter that stays idle long enough to refill a few more
        // tokens than the burst allows
        let rateLimiter = RateLimiter(rate: 10, burst: 2)
        try await Task.sleep(for: .milliseconds(300))

        // WHEN
        var isExecuted = Array(repeating: false, count: 5)
        for i in isExecuted.indices {
            rateLimiter.execute {
                isExecuted[i] = true
                return true
            }
        }

        // THEN only the burst runs right away. Every extra item would need the
        // test to stall for another 100 ms, so the last two leave a wide margin.
        #expect(isExecuted[0])
        #expect(isExecuted[1])
        #expect(!isExecuted[3])
        #expect(!isExecuted[4])
    }
}
