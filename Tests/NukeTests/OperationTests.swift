// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite @ImagePipelineActor struct OperationTests {
    let queue = JobQueue(maxConcurrentJobCount: 1)

    @Test func basics() async {
        // Given
        let operation = Nuke.Operation { .success(42) }

        // When
        let expectation = AsyncExpectation<Int>()
        operation.receive {
            switch $0 {
            case .success(let value):
                expectation.fulfill(with: value)
            case .failure:
                Issue.record()
            }
        }
        queue.enqueue(operation)

        // Then
        let value = await expectation.value
        #expect(value == 42)
    }

    @Test func priority() async {
        // Given
        let operation = Nuke.Operation { .success(42) }
        let owner = MockJobOwner()
        owner.priority = .high

        // When
        operation.receive(owner) { _ in }

        // Then
        #expect(operation.priority == .high)
    }
}

final class MockJobOwner: JobOwner {
    var priority: JobPriority = .normal

    func addSubscribedTasks(to output: inout [ImageTask]) {
        // Do nothing
    }
}
