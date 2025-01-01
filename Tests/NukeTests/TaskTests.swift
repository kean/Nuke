// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite @ImagePipelineActor struct TaskTests {
    // MARK: - Starter

    @Test func starterCalledOnFirstSubscription() {
        // Given
        var startCount = 0
        _ = SimpleTask<Int, Error>(starter: { _ in
            startCount += 1
        })

        // Then
        #expect(startCount == 0)
    }

    @Test func starterCalledWhenSubscriptionIsAdded() {
        // Given
        var startCount = 0
        let task = SimpleTask<Int, Error>(starter: { _ in
            startCount += 1
        })

        // When first subscription is added
        _ = task.subscribe { _ in }

        // Then started is called
        #expect(startCount == 1)
    }

    @Test func starterOnlyCalledOnce() {
        // Given
        var startCount = 0
        let task = SimpleTask<Int, Error>(starter: { _ in
            startCount += 1
        })

        // When two subscriptions are added
        _ = task.subscribe { _ in }
        _ = task.subscribe { _ in }

        // Then started is only called once
        #expect(startCount == 1)
    }

    @Test func tarterIsDeallocated() {
        // Given
        class Foo {
        }

        weak var weakFoo: Foo?

        let task: AsyncTask<Int, Error> = autoreleasepool { // Just in case
            let foo = Foo()
            weakFoo = foo
            return SimpleTask<Int, Error>(starter: { _ in
                _ = foo // Retain foo
            })
        }

        #expect(weakFoo != nil, "Foo is retained by starter")

        // When first subscription is added and starter is called
        _ = task.subscribe { _ in }

        // Then
        #expect(weakFoo == nil, "Started wasn't deallocated")
    }

    // MARK: - Subscribe

    @Test func whenSubscriptionAddedEventsAreForwarded() {
        // Given
        let task = SimpleTask<Int, MyError>(starter: {
            $0.send(progress: TaskProgress(completed: 1, total: 2))
            $0.send(value: 1)
            $0.send(progress: TaskProgress(completed: 2, total: 2))
            $0.send(value: 2, isCompleted: true)
        })

        // When
        var recordedEvents = [AsyncTask<Int, MyError>.Event]()
        _ = task.subscribe { event in
            recordedEvents.append(event)
        }

        // Then
        #expect(recordedEvents == [
            .progress(TaskProgress(completed: 1, total: 2)),
            .value(1, isCompleted: false),
            .progress(TaskProgress(completed: 2, total: 2)),
            .value(2, isCompleted: true)
        ])
    }

    @Test func bothSubscriptionsReceiveEvents() {
        // Given
        let task = AsyncTask<Int, MyError>()

        // When there are two subscriptions
        var eventCount = 0

        _ = task.subscribe { event in
            #expect(event == .value(1, isCompleted: false))
            eventCount += 1 }
        _ = task.subscribe {  event in
            #expect(event == .value(1, isCompleted: false))
            eventCount += 1
        }

        task.send(value: 1)

        // Then
        #expect(eventCount == 2)
    }

    @Test func cantSubscribeToAlreadyCancelledTask() {
        // Given
        let task = SimpleTask<Int, MyError>(starter: { _ in })
        let subscription = task.subscribe { _ in }

        // When
        subscription?.unsubscribe()

        // Then
        #expect(task.subscribe { _ in } == nil)
    }

    @Test func cantSubscribeToAlreadySucceededTask() {
        // Given
        let task = AsyncTask<Int, MyError>()
        _ = task.subscribe { _ in }

        // When
        task.send(value: 1, isCompleted: true)

        // Then
        #expect(task.subscribe { _ in } == nil)
    }

    @Test func cantSubscribeToAlreadyFailedTasks() {
        // Given
        let task = AsyncTask<Int, MyError>()
        _ = task.subscribe { _ in }

        // When
        task.send(error: .init(raw: "1"))

        // Then
        #expect(task.subscribe { _ in } == nil)
    }

    @Test func subscribeToTaskWithSynchronousCompletionReturnsNil() async {
        // Given
        let task = SimpleTask<Int, MyError> { (task) in
            task.send(value: 0, isCompleted: true)
        }

        // When/Then
        await withUnsafeContinuation { continuation in
            let subscription = task.subscribe { _ in
                continuation.resume()
            }
            #expect(subscription == nil)
        }
    }

    // MARK: - Ubsubscribe

    @Test func whenSubscriptionIsRemovedNoEventsAreSent() {
        // Given
        let task = AsyncTask<Int, MyError>()
        var recordedEvents = [AsyncTask<Int, MyError>.Event]()
        let subscription = task.subscribe { recordedEvents.append($0) }

        // When
        subscription?.unsubscribe()
        task.send(value: 1)

        // Then
        #expect(recordedEvents.isEmpty, "Expect no events to be received by observer after subscription is removed")
    }

    @Test func whenSubscriptionIsRemovedTaskBecomesDisposed() {
        // Given
        let task = AsyncTask<Int, MyError>()
        let subscription = task.subscribe { _ in }

        // When
        subscription?.unsubscribe()

        // Then
        #expect(task.isDisposed, "Expect task to be marked as disposed")
    }

    @Test func whenSubscriptionIsRemovedOnCancelIsCalled() {
        // Given
        let task = AsyncTask<Int, MyError>()
        let subscription = task.subscribe { _ in }

        var onCancelledIsCalled = false
        task.onCancelled = {
            onCancelledIsCalled = true
        }

        // When
        subscription?.unsubscribe()

        // Then
        #expect(onCancelledIsCalled)
    }

    @Test func whenSubscriptionIsRemovedOperationIsCancelled() {
        // Given
        let operation = Foundation.Operation()
        let task = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let subscription = task.subscribe { _ in }
        #expect(!operation.isCancelled)

        // When
        subscription?.unsubscribe()

        // Then
        #expect(operation.isCancelled)
    }

    @Test func whenSubscriptionIsRemovedDependencyIsCancelled() {
        // Given
        let operation = Foundation.Operation()
        let dependency = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let task = SimpleTask<Int, MyError>(starter: { $0.dependency = dependency.subscribe { _ in } })
        let subscription = task.subscribe { _ in }
        #expect(!operation.isCancelled)

        // When
        subscription?.unsubscribe()

        // Then
        #expect(operation.isCancelled)
    }

    @Test func whenOneOfTwoSubscriptionsAreRemovedTaskNotCancelled() {
        // Given
        let operation = Foundation.Operation()
        let task = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let subscription1 = task.subscribe { _ in }
        _ = task.subscribe { _ in }

        // When
        subscription1?.unsubscribe()

        // Then
        #expect(!operation.isCancelled)
    }

    @Test func whenTwoOfTwoSubscriptionsAreRemovedTaskIsCancelled() {
        // Given
        let operation = Foundation.Operation()
        let task = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let subscription1 = task.subscribe { _ in }
        let subscription2 = task.subscribe { _ in }

        // When
        subscription1?.unsubscribe()
        subscription2?.unsubscribe()

        // Then
        #expect(operation.isCancelled)
    }

    // MARK: - Priority

    @Test func whenPriorityIsUpdatedOperationPriorityAlsoUpdated() {
        // Given
        let operation = Foundation.Operation()
        let task = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let subscription = task.subscribe { _ in }

        // When
        subscription?.setPriority(.high)

        // Then
        #expect(operation.queuePriority == .high)
    }

    @Test func whenTaskChangesOperationPriorityUpdated() { // Or sets operation later
        // Given
        let task = AsyncTask<Int, MyError>()
        let subscription = task.subscribe { _ in }

        // When
        subscription?.setPriority(.high)
        let operation = Foundation.Operation()
        task.operation = operation

        // Then
        #expect(operation.queuePriority == .high)
    }

    @Test func priorityCanBeLowered() {
        // Given
        let operation = Foundation.Operation()
        let task = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let subscription = task.subscribe { _ in }

        // When
        subscription?.setPriority(.low)

        // Then
        #expect(operation.queuePriority == .low)
    }

    @Test func priorityEqualMaximumPriorityOfAllSubscriptions() {
        // Given
        let operation = Foundation.Operation()
        let task = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let subscription1 = task.subscribe { _ in }
        let subscription2 = task.subscribe { _ in }

        // When
        subscription1?.setPriority(.low)
        subscription2?.setPriority(.high)

        // Then
        #expect(operation.queuePriority == .high)
    }

    @Test func subscriptionIsRemovedPriorityIsUpdated() {
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
        #expect(operation.queuePriority == .low)
    }

    @Test func whenSubscriptionLowersPriorityButExistingSubscriptionHasHigherPriporty() {
        // Given
        let operation = Foundation.Operation()
        let task = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let subscription1 = task.subscribe { _ in }
        let subscription2 = task.subscribe { _ in }

        // When
        subscription2?.setPriority(.high)
        subscription1?.setPriority(.low)

        // Then order of updating sub
        #expect(operation.queuePriority == .high)
    }

    @Test func priorityOfDependencyUpdated() {
        // Given
        let operation = Foundation.Operation()
        let dependency = SimpleTask<Int, MyError>(starter: { $0.operation = operation })
        let task = SimpleTask<Int, MyError>(starter: { $0.dependency = dependency.subscribe { _ in } })
        let subscription = task.subscribe { _ in }

        // When
        subscription?.setPriority(.high)

        // Then
        #expect(operation.queuePriority == .high)
    }

    // MARK: - Dispose

    @Test func executingTaskIsntDisposed() {
        // Given
        let task = AsyncTask<Int, MyError>()
        var isDisposeCalled = false
        task.onDisposed = { isDisposeCalled = true }
        _ = task.subscribe { _ in }

        // When
        task.send(value: 1) // Casually sending value

        // Then
        #expect(!isDisposeCalled)
        #expect(!task.isDisposed)
    }

    @Test func taskIsDisposedWhenCancelled() {
        // Given
        let task = SimpleTask<Int, MyError>(starter: { _ in })
        var isDisposeCalled = false
        task.onDisposed = { isDisposeCalled = true }
        let subscription = task.subscribe { _ in }

        // When
        subscription?.unsubscribe()

        // Then
        #expect(isDisposeCalled)
        #expect(task.isDisposed)
    }

    @Test func taskIsDisposedWhenCompletedWithSuccess() {
        // Given
        let task = AsyncTask<Int, MyError>()
        var isDisposeCalled = false
        task.onDisposed = { isDisposeCalled = true }
        _ = task.subscribe { _ in }

        // When
        task.send(value: 1, isCompleted: true)

        // Then
        #expect(isDisposeCalled)
        #expect(task.isDisposed)
    }

    @Test func taskIsDisposedWhenCompletedWithFailure() {
        // Given
        let task = AsyncTask<Int, MyError>()
        var isDisposeCalled = false
        task.onDisposed = { isDisposeCalled = true }
        _ = task.subscribe { _ in }

        // When
        task.send(error: .init(raw: "1"))

        // Then
        #expect(isDisposeCalled)
        #expect(task.isDisposed)
    }
}

// MARK: - Helpers

private struct MyError: Equatable {
    let raw: String
}

private final class SimpleTask<T, E>: AsyncTask<T, E>, @unchecked Sendable {
    private var starter: ((SimpleTask) -> Void)?

    /// Initializes the task with the `starter`.
    /// - parameter starter: The closure which gets called as soon as the first
    /// subscription is added to the task. Only gets called once and is immediately
    /// deallocated after it is called.
    init(starter: ((SimpleTask) -> Void)? = nil) {
        self.starter = starter
    }

    override func start() {
        starter?(self)
        starter = nil
    }
}

extension AsyncTask {
    func subscribe(priority: TaskPriority = .normal, _ observer: @escaping (Event) -> Void) -> TaskSubscription? {
        publisher.subscribe(priority: priority, subscriber: "" as AnyObject, observer)
    }
}
