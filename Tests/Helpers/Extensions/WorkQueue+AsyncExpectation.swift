import Foundation
import Combine
import Testing

@testable import Nuke

extension WorkQueue {
    func expectItemAdded() -> AsyncExpectation<WorkQueue.Item> {
        let expectation = AsyncExpectation<WorkQueue.Item>()
        onEvent = { event in
            if case .added(let item) = event {
                expectation.fulfill(with: item)
            }
        }
        return expectation
    }

    func expectItemAdded(count: Int) -> AsyncExpectation<[WorkQueue.Item]> {
        let expectation = AsyncExpectation<[WorkQueue.Item]>()
        var items: [WorkQueue.Item] = []
        onEvent = { event in
            if case .added(let item) = event {
                items.append(item)
                if items.count == count {
                    expectation.fulfill(with: items)
                } else if items.count > count {
                    Issue.record("Unexpectedly received more than \(count) items")
                }
            }
        }
        return expectation
    }

    func expectPriorityUpdated(for expectedItem: WorkQueue.Item) -> AsyncExpectation<TaskPriority> {
        let expectation = AsyncExpectation<TaskPriority>()
        onEvent = { event in
            if case let .priorityUpdated(item, priority) = event {
                if item === expectedItem {
                    expectation.fulfill(with: priority)
                }
            }
        }
        return expectation
    }

    func expectItemCancelled(_ expectedItem: WorkQueue.Item) -> AsyncExpectation<Void> {
        let expectation = AsyncExpectation<Void>()
        onEvent = { event in
            if case .cancelled(let item) = event {
                if item === expectedItem {
                    expectation.fulfill()
                }
            }
        }
        return expectation
    }
}
