// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite @ImagePipelineActor struct JobQueueTests {
    let queue = JobQueue(maxConcurrentJobCount: 1)

    // MARK: Basics

    // Make sure that you submit N tasks where N is greater than `maxConcurrentJobCount`,
    // all tasks get executed.
    @Test func basics() async {
        await confirmation(expectedCount: 4) { confirmation in
            await withTaskGroup(of: Void.self) { group in
                for _ in Array(0..<4) {
                    group.addTask { @Sendable @ImagePipelineActor in
                        await withUnsafeContinuation { continuation in
                            let job = TestJob {
                                try? await Task.sleep(nanoseconds: 100)
                            }
                            job.queue = queue
                            job.subscribe { event in
                                confirmation()
                                continuation.resume()
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func executionOrder() async {
        // When
        queue.isSuspended = true

        var completed: [Int] = []

        queue.add({ completed.append(1) }).subscribe { _  in }
        queue.add({ completed.append(2) }).subscribe { _  in }
        queue.add({ completed.append(3) }).subscribe { _  in }

        queue.isSuspended = false

        // Then items are executed in the order they were added (FIFO)
        await queue.wait()
        #expect(completed == [1, 2, 3])
    }

    // MARK: Cancellation

    @Test func cancelPendingWork() async {
        queue.isSuspended = true

        var isFirstTaskExecuted = false
        let job = queue.add {
            isFirstTaskExecuted = true
        }

        job.simulateCancel()

        #expect(!isFirstTaskExecuted)

        queue.isSuspended = false

        await confirmation { confirmation in
            await withUnsafeContinuation { continuation in
                queue.add {
                    confirmation()
                    continuation.resume()
                }.subscribe({ _ in })
            }
        }
    }

    @Test func cancelInFlightWork() async {
        @ImagePipelineActor final class Context {
            var continuation: UnsafeContinuation<Void, Never>?
            var subscription: JobSubscription?
        }
        let context = Context()
        context.subscription = queue.add {
            await withTaskCancellationHandler {
                await withUnsafeContinuation {
                    context.continuation = $0
                    Task { @ImagePipelineActor in
                        #expect(context.subscription != nil)
                        context.subscription?.unsubscribe()
                    }
                }
            } onCancel: {
                Task { @ImagePipelineActor in
                    context.continuation?.resume()
                }
            }
        }.subscribe({ _ in })?.subscription
    }

    // MARK: Priority

    @Test func executionBasedOnPriority() async {
        queue.isSuspended = true

        var completed: [Int] = []

        queue.add {
            completed.append(1)
        }.subscribe(priority: .low) { _ in }

        queue.add {
            completed.append(2)
        }.subscribe(priority: .high, { _ in })

        queue.add {
            completed.append(3)
        }.subscribe(priority: .normal, { _ in })

        queue.isSuspended = false

        await queue.wait()

        #expect(completed == [2, 3, 1])
    }

    @Test func changePriorityOfScheduldItem() async {
        // Given a queue with priorities [2, 3, 1]
        queue.isSuspended = true

        var completed: [Int] = []

        let subscriber1 = queue.add {
            completed.append(1)
        }.subscribe(priority: .low) { _ in }

        queue.add {
            completed.append(2)
        }.subscribe(priority: .high, { _ in })

        queue.add {
            completed.append(3)
        }.subscribe(priority: .normal, { _ in })

        // When item with .low priority (1) changes priority to .high
        subscriber1?.setPriority(.high)

        // Then
        queue.isSuspended = false
        await queue.wait()
        #expect(completed == [2, 1, 3])
    }
}

extension JobQueue {
    @discardableResult
    func add<Value: Sendable>(_ closure: @ImagePipelineActor @Sendable @escaping () async throws(ImageTask.Error) -> Value) -> TestJob<Value> {
        let job = TestJob(closure: closure)
        job.queue = self
        return job
    }

    func wait() async {
        var count = executingJobs.count + scheduledJobs.map(\.count).reduce(0, +)
        guard count > 0 else {
            return
        }
        let expectation = AsyncExpectation<Void>()
        onEvent = {
            if case .disposed = $0 {
                count -= 1
                if count == 0 {
                    expectation.fulfill()
                }
            }
        }
        return await expectation.wait()
    }
}

extension Job {
    func simulateCancel() {
        subscribe({ _ in })?.unsubscribe()
    }
}

final class TestJob<Value: Sendable>: Job<Value> {
    let closure: @ImagePipelineActor @Sendable () async throws(ImageTask.Error) -> Value

    private var task: Task<Void, Never>?

    /// Initialize the task with the given closure to be executed in the background.
    init(closure: @ImagePipelineActor @Sendable @escaping () async throws(ImageTask.Error) -> Value) {
        self.closure = closure
        super.init()
    }

    override func start() {
        task = Task {
            do {
                let value = try await self.closure()
                self.send(value: value, isCompleted: true)
            } catch {
                // swiftlint:disable:next force_cast
                self.send(error: error as! ImageTask.Error)
            }
        }
    }

    override func onCancel() {
        task?.cancel()
    }
}
