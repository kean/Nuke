// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class RateLimiterTests: XCTestCase {
    var rateLimiter: RateLimiter!

    override func setUp() {
        super.setUp()

        // Note: we set very short rate to avoid bucket form being refilled too quickly
        rateLimiter = RateLimiter(rate: 10, burst: 2)
    }

    @ImagePipelineActor
    func testThatBurstIsExecutedimmediately() {
        // Given
        var isExecuted = Array(repeating: false, count: 4)

        // When
        for i in isExecuted.indices {
            rateLimiter.execute {
                isExecuted[i] = true
                return true
            }
        }

        // Then
        XCTAssertEqual(isExecuted, [true, true, false, false], "Expect first 2 items to be executed immediately")
    }

    @ImagePipelineActor
    func testThatNotExecutedItemDoesntExtractFromBucket() {
        // Given
        var isExecuted = Array(repeating: false, count: 4)

        // When
        for i in isExecuted.indices {
            rateLimiter.execute {
                isExecuted[i] = true
                return i != 1 // important!
            }
        }

        // Then
        XCTAssertEqual(isExecuted, [true, true, true, false], "Expect first 2 items to be executed immediately")
    }
    
    @ImagePipelineActor
    func testOverflow() {
        // Given
        var isExecuted = Array(repeating: false, count: 3)
        
        // When
        let expectation = self.expectation(description: "All work executed")
        expectation.expectedFulfillmentCount = isExecuted.count
        
        for i in isExecuted.indices {
            rateLimiter.execute {
                isExecuted[i] = true
                expectation.fulfill()
                return true
            }
        }
        
        // When time is passed
        wait()
        
        // Then
        XCTAssertEqual(isExecuted, [true, true, true], "Expect 3rd item to be executed after a short delay")
    }
}
