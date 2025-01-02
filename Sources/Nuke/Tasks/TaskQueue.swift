
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
        let veryLow = LinkedList<ScheduledTask>()
        let low = LinkedList<ScheduledTask>()
        let normal = LinkedList<ScheduledTask>()
        let high = LinkedList<ScheduledTask>()
        let veryHigh = LinkedList<ScheduledTask>()

        lazy var all = [veryHigh, high, normal, low, veryLow]
    }

    private var pendingTasks = ScheduledTasks()
    private var activeTaskCount = 0
    private let maxConcurrentTaskCount: Int

    // TODO: add isSuspended support for testing

    init(maxConcurrentTaskCount: Int) {
        self.maxConcurrentTaskCount = maxConcurrentTaskCount
    }

    func enqueue(_ work: @ImagePipelineActor @escaping () async -> Void) {
        if activeTaskCount < maxConcurrentTaskCount {
            perform(work)
        } else {
            let task = ScheduledTask(work: work)
            pendingTasks.normal.append(task)
            performPendingTasks()
        }
    }

    /// Returns a pending task with a highest priority.
    private func dequeueNextTask() -> ScheduledTask? {
        for list in pendingTasks.all {
            if let node = list.popLast() {
                return node.value
            }
        }
        return nil
    }

    private func performPendingTasks() {
        while activeTaskCount < maxConcurrentTaskCount, let task = dequeueNextTask() {
            perform(task.work)
        }
    }

    private func perform(_ work: @ImagePipelineActor @escaping () async -> Void) {
        activeTaskCount += 1
        Task { @ImagePipelineActor in
            await work()
            self.activeTaskCount -= 1
            self.performPendingTasks()
        }
    }

    /// A handle that can be used to change the priority of the pending work.
    @ImagePipelineActor
    private final class ScheduledTask {
        let work: @ImagePipelineActor () async -> Void

        init(work: @ImagePipelineActor @escaping () async -> Void) {
            self.work = work
        }
    }
}
