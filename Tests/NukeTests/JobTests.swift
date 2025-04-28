// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@ImagePipelineActor
@Suite struct JobTests {
    var queue = JobQueue()

    init() {
        queue.isSuspended = true
    }

    // MARK: - Starter

    @Test func starterCalledOnFirstSubscription() {
        // Given
        var startCount = 0
        _ = SimpleJob<Int>(starter: { _ in
            startCount += 1
        })

        // Then
        #expect(startCount == 0)
    }

    @Test func starterCalledWhenSubscriptionIsAdded() {
        // Given
        var startCount = 0
        let job = SimpleJob<Int>(starter: { _ in
            startCount += 1
        })

        // When first subscription is added
        _ = job.subscribe { _ in }

        // Then started is called
        #expect(startCount == 1)
    }

    @Test func starterOnlyCalledOnce() {
        // Given
        var startCount = 0
        let job = SimpleJob<Int>(starter: { _ in
            startCount += 1
        })

        // When two subscriptions are added
        _ = job.subscribe { _ in }
        _ = job.subscribe { _ in }

        // Then started is only called once
        #expect(startCount == 1)
    }

    @Test func starterIsDeallocated() {
        // Given
        class Foo {
        }

        weak var weakFoo: Foo?

        let job: Job<Int> = autoreleasepool { // Just in case
            let foo = Foo()
            weakFoo = foo
            return SimpleJob<Int>(starter: { _ in
                _ = foo // Retain foo
            })
        }

        #expect(weakFoo != nil, "Foo is retained by starter")

        // When first subscription is added and starter is called
        _ = job.subscribe { _ in }

        // Then
        #expect(weakFoo == nil, "Started wasn't deallocated")
    }

    // MARK: - Subscribe

    @Test func whenSubscriptionAddedEventsAreForwarded() {
        // Given
        let job = SimpleJob<Int>(starter: {
            $0.send(progress: JobProgress(completed: 1, total: 2))
            $0.send(value: 1)
            $0.send(progress: JobProgress(completed: 2, total: 2))
            $0.send(value: 2, isCompleted: true)
        })

        // When
        var recordedEvents = [Job<Int>.Event]()
        _ = job.subscribe { event in
            recordedEvents.append(event)
        }

        // Then
        #expect(recordedEvents == [
            .progress(JobProgress(completed: 1, total: 2)),
            .value(1, isCompleted: false),
            .progress(JobProgress(completed: 2, total: 2)),
            .value(2, isCompleted: true)
        ])
    }

    @Test func bothSubscriptionsReceiveEvents() {
        // Given
        let job = Job<Int>()

        // When there are two subscriptions
        var eventCount = 0

        _ = job.subscribe { event in
            #expect(event == .value(1, isCompleted: false))
            eventCount += 1 }
        _ = job.subscribe {  event in
            #expect(event == .value(1, isCompleted: false))
            eventCount += 1
        }

        job.send(value: 1)

        // Then
        #expect(eventCount == 2)
    }

    @Test func cantSubscribeToAlreadyCancelledTask() {
        // Given
        let job = SimpleJob<Int>(starter: { _ in })
        let subscription = job.subscribe { _ in }

        // When
        subscription?.unsubscribe()

        // Then
        #expect(job.subscribe { _ in } == nil)
    }

    @Test func cantSubscribeToAlreadySucceededTask() {
        // Given
        let job = Job<Int>()
        _ = job.subscribe { _ in }

        // When
        job.send(value: 1, isCompleted: true)

        // Then
        #expect(job.subscribe { _ in } == nil)
    }

    @Test func cantSubscribeToAlreadyFailedTasks() {
        // Given
        let job = Job<Int>()
        _ = job.subscribe { _ in }

        // When
        job.send(error: .dataIsEmpty)

        // Then
        #expect(job.subscribe { _ in } == nil)
    }

    @Test func subscribeToTaskWithSynchronousCompletionReturnsNil() async {
        // Given
        let job = SimpleJob<Int> { job in
            job.send(value: 0, isCompleted: true)
        }

        // When/Then
        await withUnsafeContinuation { continuation in
            let subscription = job.subscribe { _ in
                continuation.resume()
            }
            #expect(subscription == nil)
        }
    }

    // MARK: - Ubsubscribe

    @Test func whenSubscriptionIsRemovedNoEventsAreSent() {
        // Given
        let job = Job<Int>()
        var recordedEvents = [Job<Int>.Event]()
        let subscription = job.subscribe { recordedEvents.append($0) }

        // When
        subscription?.unsubscribe()
        job.send(value: 1)

        // Then
        #expect(recordedEvents.isEmpty, "Expect no events to be received by observer after subscription is removed")
    }

    @Test func whenSubscriptionIsRemovedTaskBecomesDisposed() {
        // Given
        let job = Job<Int>()
        let subscription = job.subscribe { _ in }

        // When
        subscription?.unsubscribe()

        // Then
        #expect(job.isDisposed, "Expect job to be marked as disposed")
    }

 // TODO: reimplement these tests

//    @Test func whenSubscriptionIsRemovedOperationIsCancelled() async {
//        // When
//        let operation = queue.add {}
//        let job = SimpleJob<Int>(starter: { $0.operation = operation })
//        let subscription = job.subscribe { _ in }
//
//        // When
//        let expectation = queue.expectJobCancelled(operation)
//        subscription?.unsubscribe()
//
//        // Then
//        await expectation.wait()
//    }
//
//    @Test func whenSubscriptionIsRemovedDependencyIsCancelled() async {
//        // Given
//        let operation = queue.add {}
//        let dependency = SimpleJob<Int>(starter: { $0.operation = operation })
//        let job = SimpleJob<Int>(starter: {
//            $0.dependency = dependency.subscribe { _ in }?.subscription
//        })
//        let subscription = job.subscribe { _ in }
//
//        // When
//        let expectation = queue.expectJobCancelled(operation)
//        subscription?.unsubscribe()
//
//        // Then
//        await expectation.wait()
//    }
//
//    @Test func whenOneOfTwoSubscriptionsAreRemovedTaskNotCancelled() async {
//        // Given
//        let compleded = AsyncExpectation<Void>()
//        let operation = queue.add {
//            compleded.fulfill()
//        }
//        let job = SimpleJob<Int>(starter: { $0.operation = operation })
//        let subscription1 = job.subscribe { _ in }
//        _ = job.subscribe { _ in }
//
//        // When
//        subscription1?.unsubscribe()
//        Task { @ImagePipelineActor in
//            queue.isSuspended = false
//        }
//
//        // Then
//        await compleded.wait()
//    }
//
//    @Test func whenTwoOfTwoSubscriptionsAreRemovedTaskIsCancelled() async {
//        // Given
//        let operation = queue.add {}
//        let job = SimpleJob<Int>(starter: { $0.operation = operation })
//        let subscription1 = job.subscribe { _ in }
//        let subscription2 = job.subscribe { _ in }
//
//        // When
//        let expectation = queue.expectJobCancelled(operation)
//        subscription1?.unsubscribe()
//        subscription2?.unsubscribe()
//
//        // Then
//        await expectation.wait()
//    }
//
//    // MARK: - Priority
//
//    @Test func whenPriorityIsUpdatedOperationPriorityAlsoUpdated() async {
//        // Given
//        let operation = queue.add {}
//        let job = SimpleJob<Int>(starter: { $0.operation = operation })
//        let subscription = job.subscribe { _ in }
//
//        // When
//        let expecation = queue.expectPriorityUpdated(for: operation)
//        subscription?.setPriority(.high)
//
//        // Then
//        let priority = await expecation.value
//        #expect(priority == .high)
//    }
//
//    @Test func priorityCanBeLowered() async {
//        // Given
//        let operation = queue.add {}
//        let job = SimpleJob<Int>(starter: { $0.operation = operation })
//        let subscription = job.subscribe { _ in }
//
//        // When
//        let expecation = queue.expectPriorityUpdated(for: operation)
//        subscription?.setPriority(.low)
//
//        // Then
//        let priority = await expecation.value
//        #expect(priority == .low)
//    }
//
//    @Test func priorityEqualMaximumPriorityOfAllSubscriptions() async {
//        // Given
//        let operation = queue.add {}
//        let job = SimpleJob<Int>(starter: { $0.operation = operation })
//        let subscription1 = job.subscribe { _ in }
//        let subscription2 = job.subscribe { _ in }
//
//        // When
//        let expecation = queue.expectPriorityUpdated(for: operation)
//        subscription1?.setPriority(.low)
//        subscription2?.setPriority(.high)
//
//        // Then
//        #expect(await expecation.value == .high)
//    }
//
//    @Test func subscriptionIsRemovedPriorityIsUpdated() async {
//        // Given
//        let operation = queue.add {}
//        let job = SimpleJob<Int>(starter: { $0.operation = operation })
//        let subscription1 = job.subscribe { _ in }
//        let subscription2 = job.subscribe { _ in }
//
//        subscription1?.setPriority(.low)
//        subscription2?.setPriority(.high)
//
//        // When
//        let expecation = queue.expectPriorityUpdated(for: operation)
//        subscription2?.unsubscribe()
//
//        // Then
//        #expect(await expecation.value == .low)
//    }
//
//    @Test func whenSubscriptionLowersPriorityButExistingSubscriptionHasHigherPriporty() async {
//        // Given
//        let operation = queue.add {}
//        let job = SimpleJob<Int>(starter: { $0.operation = operation })
//        let subscription1 = job.subscribe { _ in }
//        let subscription2 = job.subscribe { _ in }
//
//        // When
//        let expecation = queue.expectPriorityUpdated(for: operation)
//        subscription2?.setPriority(.high)
//        subscription1?.setPriority(.low)
//
//        // Then order of updating sub
//        #expect(await expecation.value == .high)
//    }
//
//    @Test func priorityOfDependencyUpdated() async {
//        // Given
//        let operation = queue.add {}
//        let dependency = SimpleJob<Int>(starter: { $0.operation = operation })
//        let job = SimpleJob<Int>(starter: {
//            $0.dependency = dependency.subscribe { _ in }?.subscription
//        })
//        let subscription = job.subscribe { _ in }
//
//        // When
//        let expecation = queue.expectPriorityUpdated(for: operation)
//        subscription?.setPriority(.high)
//
//        // Then
//        #expect(await expecation.value == .high)
//    }

    // MARK: - Dispose

    @Test func executingTaskIsntDisposed() {
        // Given
        let job = Job<Int>()
        var isDisposeCalled = false
        job.onDisposed = { isDisposeCalled = true }
        _ = job.subscribe { _ in }

        // When
        job.send(value: 1) // Casually sending value

        // Then
        #expect(!isDisposeCalled)
        #expect(!job.isDisposed)
    }

    @Test func taskIsDisposedWhenCancelled() {
        // Given
        let job = SimpleJob<Int>(starter: { _ in })
        var isDisposeCalled = false
        job.onDisposed = { isDisposeCalled = true }
        let subscription = job.subscribe { _ in }

        // When
        subscription?.unsubscribe()

        // Then
        #expect(isDisposeCalled)
        #expect(job.isDisposed)
    }

    @Test func taskIsDisposedWhenCompletedWithSuccess() {
        // Given
        let job = Job<Int>()
        var isDisposeCalled = false
        job.onDisposed = { isDisposeCalled = true }
        _ = job.subscribe { _ in }

        // When
        job.send(value: 1, isCompleted: true)

        // Then
        #expect(isDisposeCalled)
        #expect(job.isDisposed)
    }

    @Test func taskIsDisposedWhenCompletedWithFailure() {
        // Given
        let job = Job<Int>()
        var isDisposeCalled = false
        job.onDisposed = { isDisposeCalled = true }
        _ = job.subscribe { _ in }

        // When
        job.send(error: .cancelled)

        // Then
        #expect(isDisposeCalled)
        #expect(job.isDisposed)
    }
}

// MARK: - Helpers

private final class SimpleJob<T>: Job<T>, @unchecked Sendable {
    private var starter: ((SimpleJob) -> Void)?

    /// Initializes the job with the `starter`.
    /// - parameter starter: The closure which gets called as soon as the first
    /// subscription is added to the job. Only gets called once and is immediately
    /// deallocated after it is called.
    init(starter: ((SimpleJob) -> Void)? = nil) {
        self.starter = starter
    }

    override func start() {
        starter?(self)
        starter = nil
    }
}

extension Job {
    @discardableResult
    func subscribe(priority: JobPriority = .normal, _ closure: @ImagePipelineActor @Sendable @escaping (Event) -> Void) -> JobSubscriptionHandle<Value>? {
        let subscriber = AnonymousJobSubscriber(closure: closure)
        subscriber.priority = priority
        guard let subcription = subscribe(subscriber) else {
            return nil
        }
        return JobSubscriptionHandle(subscriber: subscriber, subscription: subcription)
    }
}

/// For convenience.
@ImagePipelineActor
struct JobSubscriptionHandle<Value: Sendable> {
    let subscriber: AnonymousJobSubscriber<Value>
    let subscription: JobSubscription

    func setPriority(_ priority: JobPriority) {
        subscriber.priority = priority
        subscription.didChangePriority(priority)
    }

    func unsubscribe() {
        subscription.unsubscribe()
    }
}

final class AnonymousJobSubscriber<Value: Sendable>: JobSubscriber, Sendable {
    var priority: JobPriority = .normal

    let closure: @ImagePipelineActor @Sendable (Job<Value>.Event) -> Void

    init(closure: @ImagePipelineActor @Sendable @escaping (Job<Value>.Event) -> Void) {
        self.closure = closure
    }

    func receive(_ event: Job<Value>.Event) {
        closure(event)
    }

    func addSubscribedTasks(to output: inout [ImageTask]) {
        // Do nothing
    }
}

extension Job.Event: @retroactive Equatable where Value: Equatable {
    public static func == (lhs: Job.Event, rhs: Job.Event) -> Bool {
        switch (lhs, rhs) {
        case (let .value(lhs0, lhs1), let .value(rhs0, rhs1)): (lhs0, lhs1) == (rhs0, rhs1)
        case (let .progress(lhs), let .progress(rhs)): lhs == rhs
        case (let .error(lhs), let .error(rhs)): lhs == rhs
        default: false
        }
    }
}
