// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class RateLimiterTests: XCTestCase {
    let queue = DispatchQueue(label: "RateLimiterTests")
    var rateLimiter: RateLimiter!

    override func setUp() {
        rateLimiter = RateLimiter(queue: queue, rate: 3, burst: 2)
    }

    func testThatBurstIsExecutedImmediatelly() {
        // Given
        let cts = _CancellationTokenSource()
        var isExecuted = Array(repeating: false, count: 3)

        // When
        rateLimiter.execute(token: cts.token) {
            isExecuted[0] = true
        }

        rateLimiter.execute(token: cts.token) {
            isExecuted[1] = true
        }

        rateLimiter.execute(token: cts.token) {
            isExecuted[2] = true
        }

        // Then
        XCTAssertEqual(isExecuted, [true, true, false])
    }

    // MARK: - Cancellation

    func testThatCancelledTaskIsNotExecuted() {
        // Given
        let cts = _CancellationTokenSource()
        var isExecuted = false

        cts.cancel()

        // When
        rateLimiter.execute(token: cts.token) {
            isExecuted = true
        }

        // Then
        XCTAssertFalse(isExecuted)
    }

    func testThatCancelledPendingTaskIsNotExecuted() {
        rateLimiter.execute(token: token) {}
        rateLimiter.execute(token: token) {}

        let cts = _CancellationTokenSource()
        rateLimiter.execute(token: cts.token) {
            XCTFail()
        }
        cts.cancel()

        let expectation = self.expectation(description: "")
        rateLimiter.execute(token: token) {
            expectation.fulfill()
        }

        wait()
    }
}

private var token: _CancellationToken {
    return _CancellationTokenSource().token
}
