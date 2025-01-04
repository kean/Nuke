// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

@ImagePipelineActor
final class WorkQueue {
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

    nonisolated init(maxConcurrentTaskCount: Int) {
        self.maxConcurrentTaskCount = maxConcurrentTaskCount
    }

    @discardableResult
    func add(priority: TaskPriority = .normal, work: @ImagePipelineActor @escaping () async -> Void) -> WorkItem {
        let item = WorkItem(priority: priority, work: work)
        item.queue = self
        if !isSuspended && activeTaskCount < maxConcurrentTaskCount {
            perform(item)
        } else {
            let node = LinkedList<WorkItem>.Node(item)
            item.node = node
            schedule.list(for: item.priority).prepend(node)
        }
        return item
    }

    // MARK: - Managing Scheduled Items

    fileprivate func setPriority(_ newPriority: TaskPriority, for item: WorkItem) {
        guard let node = item.node else {
            return /* Already executing */
        }
        // Moving nodes between queues does not require new allocations
        schedule.list(for: item.priority).remove(node)
        item.priority = newPriority
        schedule.list(for: newPriority).prepend(node)
    }

    fileprivate func cancel(_ item: WorkItem) {
        if let node = item.node {
            schedule.list(for: item.priority).remove(node)
        }
        item.task?.cancel()
        item.node = nil
        item.task = nil
        item.queue = nil
    }

    // MARK: - Performing Scheduled Work

    /// Returns a pending task with a highest priority.
    private func dequeueNextItem() -> WorkItem? {
        for list in schedule.all {
            if let node = list.popLast() {
                node.value.node = nil
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

    private func perform(_ item: WorkItem) {
        activeTaskCount += 1
        item.task = Task { @ImagePipelineActor in
            await item.work()
            item.task = nil
            self.activeTaskCount -= 1
            self.performSchduledWork()
        }
    }

    /// - warning: For testing purposes only.
    func wait() async {
        if activeTaskCount == 0 { return }
        await withUnsafeContinuation { completion = $0 }
    }

    /// A handle that can be used to change the priority of the pending work.
    @ImagePipelineActor
    final class WorkItem {
        fileprivate let work: @ImagePipelineActor () async -> Void
        fileprivate(set) var priority: TaskPriority
        fileprivate weak var node: LinkedList<WorkItem>.Node?
        fileprivate var task: Task<Void, Never>?
        fileprivate weak var queue: WorkQueue?

        fileprivate init(priority: TaskPriority, work: @ImagePipelineActor @escaping () async -> Void) {
            self.priority = priority
            self.work = work
        }

        func setPriority(_ newPriority: TaskPriority) {
            guard priority != newPriority else { return }
            queue?.setPriority(newPriority, for: self)
        }

        func cancel() {
            queue?.cancel(self)
        }
    }

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
}
