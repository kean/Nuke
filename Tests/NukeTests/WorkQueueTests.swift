// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite @ImagePipelineActor struct WorkQueueTests {
    let queue = WorkQueue(maxConcurrentTaskCount: 1)

    // MARK: Basics

    // Make sure that you submit N tasks where N is greater than `maxConcurrentTaskCount`,
    // all tasks get executed.
    @Test func basics() async {
        await confirmation(expectedCount: 4) { confirmation in
            await withTaskGroup(of: Void.self) { group in
                for _ in Array(0..<4) {
                    group.addTask { @Sendable @ImagePipelineActor in
                        await withUnsafeContinuation { continuation in
                            queue.add {
                                try? await Task.sleep(nanoseconds: 100)
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

        queue.add { completed.append(1) }
        queue.add { completed.append(2) }
        queue.add { completed.append(3) }

        queue.isSuspended = false

        // Then items are executed in the order they were added (FIFO)
        await queue.wait()
        #expect(completed == [1, 2, 3])
    }

    // MARK: Cancellation

    @Test func cancelPendingWork() async {
        queue.isSuspended = true

        var isFirstTaskExecuted = false
        let task = queue.add {
            isFirstTaskExecuted = true
        }
        task.cancel()

        queue.isSuspended = false

        await confirmation { confirmation in
            await withUnsafeContinuation { continuation in
                queue.add {
                    confirmation()
                    continuation.resume()
                }
            }
        }

        #expect(!isFirstTaskExecuted)
    }

    @Test func cancelInFlightWork() async {
        @ImagePipelineActor final class Context {
            var continuation: UnsafeContinuation<Void, Never>?
            var item: WorkQueue.Operation?
        }
        let context = Context()
        context.item = queue.add(priority: .normal) {
            await withTaskCancellationHandler {
                await withUnsafeContinuation {
                    context.continuation = $0
                    Task { @ImagePipelineActor in
                        #expect(context.item != nil)
                        context.item?.cancel()
                    }
                }
            } onCancel: {
                Task { @ImagePipelineActor in
                    context.continuation?.resume()
                }
            }
        }
    }

    // MARK: Priority

    @Test func executionBasedOnPriority() async {
        queue.isSuspended = true

        var completed: [Int] = []

        queue.add(priority: .low) {
            completed.append(1)
        }
        queue.add(priority: .high) {
            completed.append(2)
        }
        queue.add(priority: .normal) {
            completed.append(3)
        }

        queue.isSuspended = false

        await queue.wait()

        #expect(completed == [2, 3, 1])
    }

    @Test func changePriorityOfScheduldItem() async {
        // Given a queue with priorities [2, 3, 1]
        queue.isSuspended = true

        var completed: [Int] = []

        let item = queue.add(priority: .low) {
            completed.append(1)
        }
        queue.add(priority: .high) {
            completed.append(2)
        }
        queue.add(priority: .normal) {
            completed.append(3)
        }

        // When item with .low priorit (1) changes priority to .high
        item.priority = .high

        // Then
        queue.isSuspended = false
        await queue.wait()
        #expect(completed == [2, 1, 3])
    }
}
