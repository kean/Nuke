// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite @ImagePipelineActor struct WorkQueueTests {
    let sut = WorkQueue(maxConcurrentTaskCount: 1)

    // MARK: Basics

    // Make sure that you submit N tasks where N is greater than `maxConcurrentTaskCount`,
    // all tasks get executed.
    @Test func basics() async {
        await confirmation(expectedCount: 4) { confirmation in
            await withTaskGroup(of: Void.self) { group in
                for _ in Array(0..<4) {
                    group.addTask { @Sendable @ImagePipelineActor in
                        await withUnsafeContinuation { continuation in
                            sut.enqueue(.init {
                                try? await Task.sleep(nanoseconds: 100)
                                confirmation()
                                continuation.resume()
                            })
                        }
                    }
                }
            }
        }
    }

    // MARK: Cancellation

    @Test func cancelPendingWork() async {
        sut.isSuspended = true

        var isFirstTaskExecuted = false
        let task = WorkQueue.WorkItem {
            isFirstTaskExecuted = true
        }
        sut.enqueue(task)
        task.cancel()

        sut.isSuspended = false

        await confirmation { confirmation in
            await withUnsafeContinuation { continuation in
                sut.enqueue(.init {
                    confirmation()
                    continuation.resume()
                })
            }
        }

        #expect(!isFirstTaskExecuted)
    }

    @Test func cancelInFlightWork() async {
        @ImagePipelineActor final class Context {
            var continuation: UnsafeContinuation<Void, Never>?
            var item: WorkQueue.WorkItem?
        }
        let context = Context()
        let item = WorkQueue.WorkItem {
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
        context.item = item
        sut.enqueue(item)
    }

    // MARK: Priority

    @Test func executionBasedOnPriority() async {
        sut.isSuspended = true

        var completed: [Int] = []

        sut.enqueue(.init(priority: .low) {
            completed.append(1)
        })
        sut.enqueue(.init(priority: .high) {
            completed.append(2)
        })
        sut.enqueue(.init(priority: .normal) {
            completed.append(3)
        })

        sut.isSuspended = false

        await sut.wait()

        #expect(completed == [2, 3, 1])
    }
}
