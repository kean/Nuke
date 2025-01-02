// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite @ImagePipelineActor struct TaskQueueTests {
    let sut = TaskQueue(maxConcurrentTaskCount: 2)

    // Make sure that you submit N tasks where N is greater than `maxConcurrentTaskCount`,
    // all tasks get executed.
    @Test func basics() async {
        await confirmation(expectedCount: 4) { confirmation in
            await withTaskGroup(of: Void.self) { group in
                for _ in Array(0..<4) {
                    group.addTask { @Sendable @ImagePipelineActor in
                        await withUnsafeContinuation { continuation in
                            sut.enqueue {
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

    @Test func cancelPendingWork() async {

    }

    @Test func cancelInFlightWork() async {
        @ImagePipelineActor final class Context {
            var continuation: UnsafeContinuation<Void, Never>?
            var task: TaskQueue.EnqueuedTask?
        }
        let context = Context()
        context.task = sut.enqueue {
            await withTaskCancellationHandler {
                await withUnsafeContinuation {
                    context.continuation = $0
                    Task { @ImagePipelineActor in
                        #expect(context.task != nil)
                        context.task?.cancel()
                    }
                }
            } onCancel: {
                Task { @ImagePipelineActor in
                    context.continuation?.resume()
                }
            }
        }
    }
}
