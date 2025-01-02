// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation

// TODO: task priority
@ImagePipelineActor
final class WorkQueue {
    private struct ScheduledWork {
        let veryLow = LinkedList<WorkItem>()
        let low = LinkedList<WorkItem>()
        let normal = LinkedList<WorkItem>()
        let high = LinkedList<WorkItem>()
        let veryHigh = LinkedList<WorkItem>()

        lazy var all = [veryHigh, high, normal, low, veryLow]
    }

    private var scheduledWork = ScheduledWork()
    private var activeTaskCount = 0
    private let maxConcurrentTaskCount: Int

    /// Setting this property to true prevents the queue from starting any queued
    /// tasks, but already executing tasks continue to execute.
    var isSuspended = false {
        didSet {
            guard oldValue != isSuspended, !isSuspended else { return }
            performSchduledWork()
        }
    }

    init(maxConcurrentTaskCount: Int) {
        self.maxConcurrentTaskCount = maxConcurrentTaskCount
    }

    func enqueue(_ item: WorkItem) {
        if !isSuspended && activeTaskCount < maxConcurrentTaskCount {
            perform(item)
        } else {
            scheduledWork.normal.append(item)
            performSchduledWork()
        }
    }

    /// Returns a pending task with a highest priority.
    private func dequeueNextItem() -> WorkItem? {
        for list in scheduledWork.all {
            if let node = list.popLast(), !node.value.isCancelled {
                return node.value
            }
        }
        return nil
    }

    private func performSchduledWork() {
        while !isSuspended, activeTaskCount < maxConcurrentTaskCount, let item = dequeueNextItem() {
            perform(item)
        }
    }

    // TODO: test memory managemnet
    private func perform(_ item: WorkItem) {
        activeTaskCount += 1
        let work = item.work
        item.task = Task { @ImagePipelineActor in
            await work()
            self.activeTaskCount -= 1
            self.performSchduledWork()
        }
    }

    /// A handle that can be used to change the priority of the pending work.
    @ImagePipelineActor
    final class WorkItem {
        let work: @ImagePipelineActor () async -> Void
        var isCancelled = false
        var priority: TaskPriority
        var task: Task<Void, Never>?

        init(priority: TaskPriority = .normal, work: @ImagePipelineActor @escaping () async -> Void) {
            self.priority = priority
            self.work = work
        }

        func cancel() {
            isCancelled = true
            task?.cancel()
        }
    }
}
