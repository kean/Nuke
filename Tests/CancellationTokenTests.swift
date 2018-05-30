// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class CancellationTokenTests: XCTestCase {
    func testInitialState() {
        // Given
        let cts = _CancellationTokenSource()
        let token = cts.token

        // Then
        XCTAssertFalse(cts.isCancelling)
        XCTAssertFalse(token.isCancelling)
        XCTAssertFalse(cts.token.isCancelling)
    }

    func testCancellation() {
        // Given
        let cts = _CancellationTokenSource()
        let token1 = cts.token
        let token2 = cts.token

        // When
        cts.cancel()

        // Then
        XCTAssertTrue(cts.isCancelling)
        XCTAssertTrue(token1.isCancelling)
        XCTAssertTrue(token2.isCancelling)
        XCTAssertTrue(cts.token.isCancelling)
    }
    
    func testThatTheRegisteredClosureIsCalled() {
        // Given
        let cts = _CancellationTokenSource()

        // When/ Then
        let expectation = self.expectation(description: "Token Cancelled")
        cts.token.register {
            expectation.fulfill()
        }
        cts.cancel()

        wait()
    }

    func testThatTheRegisteredClosureIsCalledWhenRegisteringAfterCancellation() {
        // Given
        let cts = _CancellationTokenSource()
        cts.cancel()

        // When/Then
        var isClosureCalled = false
        cts.token.register {
            isClosureCalled = true
        }

        XCTAssertTrue(isClosureCalled)
    }

    func testMultipleClosuresRegistered() {
        // Given
        let cts = _CancellationTokenSource()
        let token = cts.token

        // When/Then
        var isClosureCalled = false
        let expectation1 = self.expectation(description: "Token Cancelled")
        token.register {
            expectation1.fulfill()
            isClosureCalled = true
        }

        let expectation2 = self.expectation(description: "Token Cancelled")
        token.register {
            expectation2.fulfill()
            isClosureCalled = true
        }

        XCTAssertFalse(isClosureCalled)

        cts.cancel()

        wait()
    }

    func testCancellingMultipleTimes() {
        // Given
        let cts = _CancellationTokenSource()
        let token = cts.token

        var callsCount = 0
        token.register {
            callsCount += 1
        }

        // When
        cts.cancel()
        cts.cancel()

        // Then
        XCTAssertEqual(callsCount, 1)
    }

    func testCancellingOneFromAnother() {
        // Given
        let cts1 = _CancellationTokenSource()
        let cts2 = _CancellationTokenSource()

        // When/Then
        let expectation = self.expectation(description: "Token Cancelled")
        cts1.token.register {
            cts2.cancel()
        }
        cts2.token.register {
            expectation.fulfill()
        }

        cts1.cancel()
        wait()
    }

    // MARK: No-op token

    func testNoOpTokenInitialState() {
        // Given
        let token = _CancellationToken.noOp

        // Then
        XCTAssertFalse(token.isCancelling)
    }

    func testNoOpToken() {
        // Given
        let token = _CancellationToken.noOp

        // When/Then
        token.register { XCTFail() }
        XCTAssertFalse(token.isCancelling)
    }
}
