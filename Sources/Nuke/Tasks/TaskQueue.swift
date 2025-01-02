
// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation

// TODO: max concurrenct task count
// TODO: task priority
// TODO: cancellation (does it need instanct cancellation? does operation have it?)
@ImagePipelineActor
final class TaskQueue {

    private struct ScheduledTasks {
        let veryLow = LinkedList<EnqueuedTask>()
        let low = LinkedList<EnqueuedTask>()
        let normal = LinkedList<EnqueuedTask>()
        let high = LinkedList<EnqueuedTask>()
        let veryHigh = LinkedList<EnqueuedTask>()

        lazy var all = [veryHigh, high, normal, low, veryLow]
    }

    private var pendingTasks = ScheduledTasks()
    private var activeTaskCount = 0
    private let maxConcurrentTaskCount: Int

    // TODO: add isSuspended support for testing

    init(maxConcurrentTaskCount: Int) {
        self.maxConcurrentTaskCount = maxConcurrentTaskCount
    }

    // TODO: should you be able to cancel the underlying task from here?
    @discardableResult func enqueue(_ work: @ImagePipelineActor @escaping () async -> Void) -> EnqueuedTask {
        let task = EnqueuedTask(work: work)
        if activeTaskCount < maxConcurrentTaskCount {
            perform(task)
        } else {
            pendingTasks.normal.append(task)
            performPendingTasks()
        }
        return task
    }

    /// Returns a pending task with a highest priority.
    private func dequeueNextTask() -> EnqueuedTask? {
        for list in pendingTasks.all {
            if let node = list.popLast() {
                return node.value
            }
        }
        return nil
    }

    private func performPendingTasks() {
        while activeTaskCount < maxConcurrentTaskCount, let task = dequeueNextTask() {
            perform(task)
        }
    }

    // TODO: there are no retain cycles, are there?
    private func perform(_ task: EnqueuedTask) {
        activeTaskCount += 1
        let work = task.work
        task.task = Task { @ImagePipelineActor in
            await work()
            self.activeTaskCount -= 1
            self.performPendingTasks()
        }
    }

    /// A handle that can be used to change the priority of the pending work.
    @ImagePipelineActor
    final class EnqueuedTask {
        let work: @ImagePipelineActor () async -> Void
        var task: Task<Void, Never>?

        init(work: @ImagePipelineActor @escaping () async -> Void) {
            self.work = work
        }

        // TODO: cancel pending tasks too
        func cancel() {
            task?.cancel()
        }
    }
}
