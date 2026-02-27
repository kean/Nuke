// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite struct RateLimiterTests {
    private let queue: DispatchQueue
    private let queueKey: DispatchSpecificKey<Void>
    private let rateLimiter: RateLimiter

    init() {
        queue = DispatchQueue(label: "com.github.kean.rate-limiter-tests")
        queueKey = DispatchSpecificKey<Void>()
        queue.setSpecific(key: queueKey, value: ())
        rateLimiter = RateLimiter(queue: queue, rate: 10, burst: 2)
    }

    @Test func burstIsExecutedImmediately() {
        // Given
        var isExecuted = Array(repeating: false, count: 4)

        // When
        for i in isExecuted.indices {
            queue.sync {
                rateLimiter.execute {
                    isExecuted[i] = true
                    return true
                }
            }
        }

        // Then
        #expect(isExecuted == [true, true, false, false])
    }

    @Test func notExecutedItemDoesntExtractFromBucket() {
        // Given
        var isExecuted = Array(repeating: false, count: 4)

        // When
        for i in isExecuted.indices {
            queue.sync {
                rateLimiter.execute {
                    isExecuted[i] = true
                    return i != 1
                }
            }
        }

        // Then
        #expect(isExecuted == [true, true, true, false])
    }

    @Test func overflow() async {
        // Given
        var isExecuted = Array(repeating: false, count: 3)

        // When
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var remaining = 3
            queue.sync {
                for i in 0..<3 {
                    rateLimiter.execute {
                        isExecuted[i] = true
                        remaining -= 1
                        if remaining == 0 {
                            continuation.resume()
                        }
                        return true
                    }
                }
            }
        }

        // Then
        queue.sync {
            #expect(isExecuted == [true, true, true])
        }
    }

    @Test func overflowItemsExecutedOnSpecificQueue() async {
        // Given
        let queueKey = self.queueKey

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var remaining = 3
            queue.sync {
                for _ in 0..<3 {
                    rateLimiter.execute {
                        // Then delayed task also executed on queue
                        #expect(DispatchQueue.getSpecific(key: queueKey) != nil)
                        remaining -= 1
                        if remaining == 0 {
                            continuation.resume()
                        }
                        return true
                    }
                }
            }
        }
    }
}
