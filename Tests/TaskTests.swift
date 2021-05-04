// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class TaskTests: XCTestCase {
    // MARK: - Starter

    func testStarterCalledOnFirstSubscription() {
        // Given
        var startCount = 0
        _ = SimpleTask<Int, Error>(starter: { _ in
            startCount += 1
        })

        // Then
        XCTAssertEqual(startCount, 0)
    }

    func testStarterCalledWhenSubscriptionIsAdded() {
        // Given
        var startCount = 0
        let task = SimpleTask<Int, Error>(starter: { _ in
            startCount += 1
        })

        // When first subscription is added
        _ = task.subscribe { _ in }

        // Then started is called
        XCTAssertEqual(startCount, 1)
    }

    func testStarterOnlyCalledOnce() {
        // Given
        var startCount = 0
        let task = SimpleTask<Int, Error>(starter: { _ in
            startCount += 1
        })

        // When two subscriptions are added
        _ = task.subscribe { _ in }
        _ = task.subscribe { _ in }

        // Then started is only called once
        XCTAssertEqual(startCount, 1)
    }

    func testStarterIsDeallocated() {
        // Given
        class Foo {
        }

        weak var weakFoo: Foo?

        let task: Task<Int, Error> = autoreleasepool { // Just in case
            let foo = Foo()
            weakFoo = foo
            return SimpleTask<Int, Error>(starter: { _ in
                _ = foo // Retain foo
            })
        }

        XCTAssertNotNil(weakFoo, "Foo is retained by starter")

        // When first subscription is added and starter is called
        _ = task.subscribe { _ in }

        // Then
        XCTAssertNil(weakFoo, "Started wasn't deallocated")
    }

    // MARK: - Subscribe

    func testWhenSubscriptionAddedEventsAreForwarded() {
        // Given
        let task = SimpleTask<Int, MyError>(starter: {
            $0.send(progress: TaskProgress(completed: 1, total: 2))
            $0.send(value: 1)
            $0.send(progress: TaskProgress(completed: 2, total: 2))
            $0.send(value: 2, isCompleted: true)
        })

        // When
        var recordedEvents = [Task<Int, MyError>.Event]()
        _ = task.subscribe { event in
            recordedEvents.append(event)
        }

        // Then
        XCTAssertEqual(recordedEvents, [
            .progress(TaskProgress(completed: 1, total: 2)),
            .value(1, isCompleted: false),
            .progress(TaskProgress(completed: 2, total: 2)),
            .value(2, isCompleted: true)
        ])
    }

    func testBothSubscriptionsReceiveEvents() {
        // Given
        let task = Task<Int, MyError>()

        // When there are two subscriptions
        var eventCount = 0

        _ = task.subscribe { event in
            XCTAssertEqual(event, .value(1, isCompleted: false))
            eventCount += 1 }
        _ = task.subscribe {  event in
            XCTAssertEqual(event, .value(1, isCompleted: false))
            eventCount += 1
        }

        task.send(value: 1)

        // Then
        XCTAssertEqual(eventCount, 2)
    }

    func testCantSubscribeToAlreadyCancelledTask() {
        // Given
        let task = SimpleTask<Int, MyError>(starter: { _ in })
        let subscription = task.subscribe { _ in }

        // When
        subscription?.unsubscribe()

        // Then
        XCTAssertNil(task.subscribe { _ in })
    }

    func testCantSubscribeToAlreadySucceededTask() {
        // Given
        let task = Task<Int, MyError>()
        let _ = task.subscribe { _ in }

        // When
        task.send(value: 1, isCompleted: true)

        // Then
        XCTAssertNil(task.subscribe { _ in })
    }

    func testCantSubscribeToAlreadyFailedTasks() {
        // Given
        let task = Task<Int, MyError>()
        let _ = task.subscribe { _ in }

        // When
        task.send(error: .init(raw: "1"))

        // Then
        XCTAssertNil(task.subscribe { _ in })
    }

    func testSubscribeToTaskWithSynchronousCompletionReturnsNil() {
        // Given
        let task = SimpleTask<Int, MyError> { (task) in
            task.send(value: 0, isCompleted: true)
        }

        // When
        let expectation = self.expectation(description: "Observer called")
        let subscription = task.subscribe { _ in
            expectation.fulfill()
        }

        // Then
        XCTAssertNil(subscription)
        wait()
    }

    // MARK: - Ubsubscribe

    func testWhenSubscriptionIsRemovedNoEventsAreSent() {
        // Given
        let task = Task<Int, MyError>()
        var recordedEvents = [Task<Int, MyError>.Event]()
        let subscription = task.subscribe { recordedEvents.append($0) }

        // When
        subscription?.unsubscribe()
        task.send(value: 1)

        // Then
        XCTAssertTrue(recordedEvents.isEmpty, "Expect no events to be received by observer after subscription is removed")
    }

    func testWhenSubscriptionIsRemovedTaskBecomesDisposed() {
        // Given
        let task = Task<Int, MyError>()
        let subscription = task.subscribe { _ in }

        // When
        subscription?.unsubscribe()

        // Then
        XCTAssertTrue(task.isDisposed, "Expect task to be marked as disposed")
    }

    func testWhenSubscriptionIsRemovedOnCancelIsCalled() {
        // Given
        let task = Task<Int, MyError>()
        let subscription = task.subscribe { _ in }

        var onCancelledIsCalled = false
        task.onCancelled = {
            onCancelledIsCalled = true
        }

        // When
        subscription?.unsubscribe()

        // Then
        XCTAssertTrue(onCancelledIsCalled)
    }

    func testWhenSubscriptionIsRemovedOperationIsCancelled() {
        // Given
        let operation = Foundation.Operation()
        let task = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let subscription = task.subscribe { _ in }
        XCTAssertFalse(operation.isCancelled)

        // When
        subscription?.unsubscribe()

        // Then
        XCTAssertTrue(operation.isCancelled)
    }

    func testWhenSubscriptionIsRemovedDependencyIsCancelled() {
        // Given
        let operation = Foundation.Operation()
        let dependency = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let task = SimpleTask<Int, MyError>(starter: { $0.dependency = dependency.subscribe { _ in} })
        let subscription = task.subscribe { _ in }
        XCTAssertFalse(operation.isCancelled)

        // When
        subscription?.unsubscribe()

        // Then
        XCTAssertTrue(operation.isCancelled)
    }

    func testWhenOneOfTwoSubscriptionsAreRemovedTaskNotCancelled() {
        // Given
        let operation = Foundation.Operation()
        let task = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let subscription1 = task.subscribe { _ in }
        let _ = task.subscribe { _ in }

        // When
        subscription1?.unsubscribe()

        // Then
        XCTAssertFalse(operation.isCancelled)
    }

    func testWhenTwoOfTwoSubscriptionsAreRemovedTaskIsCancelled() {
        // Given
        let operation = Foundation.Operation()
        let task = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let subscription1 = task.subscribe { _ in }
        let subscription2 = task.subscribe { _ in }

        // When
        subscription1?.unsubscribe()
        subscription2?.unsubscribe()

        // Then
        XCTAssertTrue(operation.isCancelled)
    }

    // MARK: - Priority

    func testWhenPriorityIsUpdatedOperationPriorityAlsoUpdated() {
        // Given
        let operation = Foundation.Operation()
        let task = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let subscription = task.subscribe { _ in }

        // When
        subscription?.setPriority(.high)

        // Then
        XCTAssertEqual(operation.queuePriority, .high)
    }

    func testWhenTaskChangesOperationPriorityUpdated() { // Or sets operation later
        // Given
        let task = Task<Int, MyError>()
        let subscription = task.subscribe { _ in }

        // When
        subscription?.setPriority(.high)
        let operation = Foundation.Operation()
        task.operation = operation

        // Then
        XCTAssertEqual(operation.queuePriority, .high)
    }

    func testThatPriorityCanBeLowered() {
        // Given
        let operation = Foundation.Operation()
        let task = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let subscription = task.subscribe { _ in }

        // When
        subscription?.setPriority(.low)

        // Then
        XCTAssertEqual(operation.queuePriority, .low)
    }

    func testThatPriorityEqualMaximumPriorityOfAllSubscriptions() {
        // Given
        let operation = Foundation.Operation()
        let task = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let subscription1 = task.subscribe { _ in }
        let subscription2 = task.subscribe { _ in }

        // When
        subscription1?.setPriority(.low)
        subscription2?.setPriority(.high)

        // Then
        XCTAssertEqual(operation.queuePriority, .high)
    }

    func testWhenSubscriptionIsRemovedPriorityIsUpdated() {
        // Given
        let operation = Foundation.Operation()
        let task = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let subscription1 = task.subscribe { _ in }
        let subscription2 = task.subscribe { _ in }

        subscription1?.setPriority(.low)
        subscription2?.setPriority(.high)

        // When
        subscription2?.unsubscribe()

        // Then
        XCTAssertEqual(operation.queuePriority, .low)
    }

    func testWhenSubscriptionLowersPriorityButExistingSubscriptionHasHigherPriporty() {
        // Given
        let operation = Foundation.Operation()
        let task = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let subscription1 = task.subscribe { _ in }
        let subscription2 = task.subscribe { _ in }

        // When
        subscription2?.setPriority(.high)
        subscription1?.setPriority(.low)

        // Then order of updating sub
        XCTAssertEqual(operation.queuePriority, .high)
    }

    func testPriorityOfDependencyUpdated() {
        // Given
        let operation = Foundation.Operation()
        let dependency = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let task = SimpleTask<Int, MyError>(starter: { $0.dependency = dependency.subscribe { _ in} })
        let subscription = task.subscribe { _ in }

        // When
        subscription?.setPriority(.high)

        // Then
        XCTAssertEqual(operation.queuePriority, .high)
    }

    // MARK: - Dispose

    func testExecutingTaskIsntDisposed() {
        // Given
        let task = Task<Int, MyError>()
        var isDisposeCalled = false
        task.onDisposed = { isDisposeCalled = true }
        let _ = task.subscribe { _ in }

        // When
        task.send(value: 1) // Casually sending value

        // Then
        XCTAssertFalse(isDisposeCalled)
        XCTAssertFalse(task.isDisposed)
    }

    func testThatTaskIsDisposedWhenCancelled() {
        // Given
        let task = SimpleTask<Int, MyError>(starter: { _ in })
        var isDisposeCalled = false
        task.onDisposed = { isDisposeCalled = true }
        let subscription = task.subscribe { _ in }

        // When
        subscription?.unsubscribe()

        // Then
        XCTAssertTrue(isDisposeCalled)
        XCTAssertTrue(task.isDisposed)
    }

    func testThatTaskIsDisposedWhenCompletedWithSuccess() {
        // Given
        let task = Task<Int, MyError>()
        var isDisposeCalled = false
        task.onDisposed = { isDisposeCalled = true }
        let _ = task.subscribe { _ in }

        // When
        task.send(value: 1, isCompleted: true)

        // Then
        XCTAssertTrue(isDisposeCalled)
        XCTAssertTrue(task.isDisposed)
    }

    func testThatTaskIsDisposedWhenCompletedWithFailure() {
        // Given
        let task = Task<Int, MyError>()
        var isDisposeCalled = false
        task.onDisposed = { isDisposeCalled = true }
        let _ = task.subscribe { _ in }

        // When
        task.send(error: .init(raw: "1"))

        // Then
        XCTAssertTrue(isDisposeCalled)
        XCTAssertTrue(task.isDisposed)
    }
}

// MARK: - Helpers

private struct MyError: Equatable {
    let raw: String
}

private final class SimpleTask<T, E>: Task<T, E> {
    private var starter: ((SimpleTask) -> Void)?

    /// Initializes the task with the `starter`.
    /// - parameter starter: The closure which gets called as soon as the first
    /// subscription is added to the task. Only gets called once and is immediatelly
    /// deallocated after it is called.
    init(starter: ((SimpleTask) -> Void)? = nil) {
        self.starter = starter
    }

    override func start() {
        starter?(self)
        starter = nil
    }
}

extension Task {
    func subscribe(priority: TaskPriority = .normal, _ observer: @escaping (Event) -> Void) -> TaskSubscription? {
        publisher.subscribe(priority: priority, observer)
    }
}
