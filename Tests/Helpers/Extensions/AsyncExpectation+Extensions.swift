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

func expect(notification: Notification.Name, object : AnyObject) -> AsyncExpectation<Void> {
    AsyncExpectation(notification: notification, object: object)
}

extension Publisher where Output: Sendable {
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

extension JobQueue {
    func expectJobAdded() -> AsyncExpectation<JobHandle> {
        let expectation = AsyncExpectation<JobHandle>()
        onEvent = { event in
            if case .added(let value) = event {
                expectation.fulfill(with: value)
            }
        }
        return expectation
    }

    func expectJobsAdded(count: Int) -> AsyncExpectation<[JobHandle]> {
        let expectation = AsyncExpectation<[JobHandle]>()
        var operations: [JobHandle] = []
        onEvent = { event in
            if case .added(let item) = event {
                operations.append(item)
                if operations.count == count {
                    expectation.fulfill(with: operations)
                } else if operations.count > count {
                    Issue.record("Unexpectedly received more than \(count) items")
                }
            }
        }
        return expectation
    }

    func expectPriorityUpdated(for job: JobHandle) -> AsyncExpectation<JobPriority> {
        let expectation = AsyncExpectation<JobPriority>()
        onEvent = { event in
            if case let .priorityUpdated(value, priority) = event {
                if value === job {
                    expectation.fulfill(with: priority)
                }
            }
        }
        return expectation
    }

    func expectJobCancelled(_ job: JobHandle) -> AsyncExpectation<Void> {
        let expectation = AsyncExpectation<Void>()
        onEvent = { event in
            if case .cancelled(let value) = event {
                if value === job {
                    expectation.fulfill()
                }
            }
        }
        return expectation
    }
}

// Just no.
extension JobQueue.JobHandle: @retroactive @unchecked Sendable {}
