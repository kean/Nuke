
// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation

// TODO: task priority
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

    /// Setting this property to true prevents the queue from starting any queued
    /// tasks, but already executing tasks continue to execute.
    var isSuspended = false {
        didSet {
            guard oldValue != isSuspended, !isSuspended else { return }
            performPendingTasks()
        }
    }

    init(maxConcurrentTaskCount: Int) {
        self.maxConcurrentTaskCount = maxConcurrentTaskCount
    }

    @discardableResult func enqueue(_ work: @ImagePipelineActor @escaping () async -> Void) -> EnqueuedTask {
        let task = EnqueuedTask(work: work)
        if !isSuspended && activeTaskCount < maxConcurrentTaskCount {
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
            if let node = list.popLast(), !node.value.isCancelled {
                return node.value
            }
        }
        return nil
    }

    private func performPendingTasks() {
        while !isSuspended, activeTaskCount < maxConcurrentTaskCount, let task = dequeueNextTask() {
            perform(task)
        }
    }

    // TODO: test memory managemnet
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
        var isCancelled = false
        var task: Task<Void, Never>?

        init(work: @ImagePipelineActor @escaping () async -> Void) {
            self.work = work
        }

        func cancel() {
            isCancelled = true
            task?.cancel()
        }
    }
}
