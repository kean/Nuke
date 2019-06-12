// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class RateLimiterTests: XCTestCase {
    var queue: DispatchQueue!
    var queueKey: DispatchSpecificKey<Void>!
    var rateLimiter: RateLimiter!

    override func setUp() {
        queue = DispatchQueue(label: "com.github.kean.rate-limiter-tests")

        queueKey = DispatchSpecificKey<Void>()
        queue.setSpecific(key: queueKey, value: ())

        // Note: we set very short rate to avoid bucket form being refilled too quickly
        rateLimiter = RateLimiter(queue: queue, rate: 10, burst: 2)
    }

    func testThatBurstIsExecutedImmediatelly() {
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
        XCTAssertEqual(isExecuted, [true, true, false, false], "Expect first 2 items to be executed immediatelly")
    }

    func testThatNotExecutedItemDoesntExtractFromBucket() {
        // Given
        var isExecuted = Array(repeating: false, count: 4)

        // When
        for i in isExecuted.indices {
            queue.sync {
                rateLimiter.execute {
                    isExecuted[i] = true
                    return i != 1 // important!
                }
            }
        }

        // Then
        XCTAssertEqual(isExecuted, [true, true, true, false], "Expect first 2 items to be executed immediatelly")
    }

    func testOverflow() {
        // Given
        var isExecuted = Array(repeating: false, count: 3)

        // When
        let expectation = self.expectation(description: "All work executed")
        expectation.expectedFulfillmentCount = isExecuted.count

        queue.sync {
            for i in isExecuted.indices {
                rateLimiter.execute {
                    isExecuted[i] = true
                    expectation.fulfill()
                    return true
                }
            }
        }

        // When time is passed
        wait()

        // Then
        queue.sync {
            XCTAssertEqual(isExecuted, [true, true, true], "Expect 3rd item to be executed after a short delay")
        }
    }

    func testOverflowItemsExecutedOnSpecificQueue() {
        // Given
        let isExecuted = Array(repeating: false, count: 3)

        let expectation = self.expectation(description: "All work executed")
        expectation.expectedFulfillmentCount = isExecuted.count

        queue.sync {
            for _ in isExecuted.indices {
                rateLimiter.execute {
                    expectation.fulfill()
                    // Then delayed task also executed on queue
                    XCTAssertNotNil(DispatchQueue.getSpecific(key: self.queueKey))
                    return true
                }
            }
        }
        wait()
    }
}
