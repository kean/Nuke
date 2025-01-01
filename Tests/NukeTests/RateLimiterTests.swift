// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

@Suite @ImagePipelineActor struct RateLimiterTests {
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
}
