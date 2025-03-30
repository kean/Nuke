import Foundation
import Combine
import Testing

@testable import Nuke

extension WorkQueue {
    func expectItemAdded() -> AsyncExpectation<WorkQueue.Item> {
        let expectation = AsyncExpectation<WorkQueue.Item>()
        onEvent = { event in
            if case .workAdded(let item) = event {
                expectation.fulfill(with: item)
            }
        }
        return expectation
    }

    func expectPriorityUpdated(for expectedItem: WorkQueue.Item) -> AsyncExpectation<TaskPriority> {
        let expectation = AsyncExpectation<TaskPriority>()
        onEvent = { event in
            if case let .priorityUpdate(item, priority) = event {
                if item === expectedItem {
                    expectation.fulfill(with: priority)
                }
            }
        }
        return expectation
    }
}
