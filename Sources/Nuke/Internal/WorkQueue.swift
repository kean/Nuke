// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

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

        func list(for priority: TaskPriority) -> LinkedList<WorkItem> {
            switch priority {
            case .veryLow: veryLow
            case .low: low
            case .normal: normal
            case .high: high
            case .veryHigh: veryHigh
            }
        }

        lazy var all = [veryHigh, high, normal, low, veryLow]
    }

    private var schedule = ScheduledWork()
    private var activeTaskCount = 0
    private let maxConcurrentTaskCount: Int
    private var completion: UnsafeContinuation<Void, Never>?

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

    @discardableResult
    func enqueue(priority: TaskPriority = .normal, work: @ImagePipelineActor @escaping () async -> Void) -> WorkItem {
        let item = WorkItem(priority: priority, work: work)
        enqueue(item)
        return item
    }

    func enqueue(_ item: WorkItem) {
        assert(item.queue == nil)
        item.queue = self
        if !isSuspended && activeTaskCount < maxConcurrentTaskCount {
            perform(item)
        } else {
            let node = LinkedList<WorkItem>.Node(item)
            item.node = node
            schedule.list(for: item.priority).prepend(node)
        }
    }

    func setPriority(_ newPriority: TaskPriority, for item: WorkItem) {
        guard let node = item.node else {
            return /* Already executing */
        }
        // Moving nodes between queues does not require new allocations
        schedule.list(for: item.priority).remove(node)
        item.priority = newPriority
        schedule.list(for: newPriority).prepend(node)
    }

    /// Returns a pending task with a highest priority.
    private func dequeueNextItem() -> WorkItem? {
        for list in schedule.all {
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
        if activeTaskCount == 0 {
            completion?.resume()
            completion = nil
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
        fileprivate let work: @ImagePipelineActor () async -> Void

        fileprivate(set) var isCancelled = false

        fileprivate(set) var priority: TaskPriority

        fileprivate weak var node: LinkedList<WorkItem>.Node?

        fileprivate var task: Task<Void, Never>?

        fileprivate weak var queue: WorkQueue?

        init(priority: TaskPriority, work: @ImagePipelineActor @escaping () async -> Void) {
            self.priority = priority
            self.work = work
        }

        func setPriority(_ newPriority: TaskPriority) {
            guard priority != newPriority else { return }
            queue?.setPriority(newPriority, for: self)
        }

        // TODO: move cancellation to WorkQueue
        func cancel() {
            isCancelled = true
            task?.cancel()
        }
    }

    /// - warning: For testing purposes onlu.
    func wait() async {
        if activeTaskCount == 0 { return }
        await withUnsafeContinuation { completion = $0 }
    }
}
