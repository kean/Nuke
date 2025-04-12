import Foundation
import Combine
import Testing

@testable import Nuke

extension AsyncExpectation where Value == Void {
    convenience init(notification: Notification.Name, object: AnyObject) {
        self.init()

        NotificationCenter.default
            .publisher(for: notification, object: object)
            .sink { [weak self] _ in self?.fulfill() }
            .store(in: &cancellables)
    }
}

extension WorkQueue {
    func expectItemAdded() -> AsyncExpectation<WorkQueue.Operation> {
        let expectation = AsyncExpectation<WorkQueue.Operation>()
        onEvent = { event in
            if case .added(let item) = event {
                expectation.fulfill(with: item)
            }
        }
        return expectation
    }

    func expectItemAdded(count: Int) -> AsyncExpectation<[WorkQueue.Operation]> {
        let expectation = AsyncExpectation<[WorkQueue.Operation]>()
        var items: [WorkQueue.Operation] = []
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

    func expectPriorityUpdated(for expectedItem: WorkQueue.Operation) -> AsyncExpectation<TaskPriority> {
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

    func expectItemCancelled(_ expectedItem: WorkQueue.Operation) -> AsyncExpectation<Void> {
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

extension Publisher {
    func expectToPublishValue() -> AsyncExpectation<Output> {
        let expectation = AsyncExpectation<Output>()
        sink(receiveCompletion: { _ in
            // Do nothing
        }, receiveValue: {
            expectation.fulfill(with: $0)
        }).store(in: &expectation.cancellables)
        return expectation
    }

    // Record values until the publisher completes.
    func record(count: Int? = nil) -> AsyncExpectation<[Output]> {
        let expectation = AsyncExpectation<[Output]>()
        var output: [Output] = []
        sink(receiveCompletion: { result in
            switch result {
            case .finished:
                if count == nil {
                    expectation.fulfill(with: output)
                }
            case .failure(let failure):
                Issue.record(failure, "Unexpected failure")
            }
        }, receiveValue: {
            output.append($0)
            if let count, output.count == count {
                expectation.fulfill(with: output)
            }
        }).store(in: &expectation.cancellables)
        return expectation
    }
}
