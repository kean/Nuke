// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Combine
@testable import Nuke

@Suite struct DataPublisherTests {
    @Test func initNotStartsExecutionRightAway() async {
        let operation = MockOperation()
        let publisher = DataPublisher(id: UUID().uuidString) {
            await operation.execute()
        }

        #expect(operation.executeCalls == 0)

        var cancellable: (any Nuke.Cancellable)?
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cancellable = publisher.sink { _ in
                continuation.resume()
            } receiveValue: { _ in }
        }
        _ = cancellable

        #expect(operation.executeCalls == 1)
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
