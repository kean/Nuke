// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
import Combine
@testable import Nuke

internal final class DataPublisherTests: XCTestCase {

    private var cancellable: (any Nuke.Cancellable)?

    func testInitNotStartsExecutionRightAway() {
        let operation = MockOperation()
        let publisher = DataPublisher(id: UUID().uuidString) {
            await operation.execute()
        }

        XCTAssertEqual(0, operation.executeCalls)

        let expOp = expectation(description: "Waits for MockOperation to complete execution")
        cancellable = publisher.sink { completion in expOp.fulfill() } receiveValue: { _ in }
        wait(for: [expOp], timeout: 0.2)

        XCTAssertEqual(1, operation.executeCalls)
    }

    private final class MockOperation: @unchecked Sendable {

        private(set) var executeCalls = 0

        func execute() async -> Data {
            executeCalls += 1
            await Task.yield()
            return Data()
        }

    }

}
