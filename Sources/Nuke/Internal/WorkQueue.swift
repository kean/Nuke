// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Combine

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

    var onEvent: ((Event) -> Void)?

    nonisolated init(maxConcurrentTaskCount: Int) {
        self.maxConcurrentTaskCount = maxConcurrentTaskCount
    }

    @discardableResult
    func add(priority: TaskPriority = .normal, work: @ImagePipelineActor @escaping () async -> Void) -> Item {
        let item = _Item(priority: priority, work: work)
        item.queue = self
        if !isSuspended && activeTaskCount < maxConcurrentTaskCount {
            perform(item)
        } else {
            let node = LinkedList<_Item>.Node(item)
            item.node = node
            schedule.list(for: item.priority).prepend(node)
        }
        onEvent?(.workAdded(item))
        return Item(item: item)
    }

    // MARK: - Managing Scheduled Items

    fileprivate func setPriority(_ newPriority: TaskPriority, for item: _Item) {
        guard let node = item.node, item.priority != newPriority else {
            return /* Already executing */
        }
        // Moving nodes between queues does not require new allocations
        schedule.list(for: item.priority).remove(node)
        item.priority = newPriority
        schedule.list(for: newPriority).prepend(node)
    }

    fileprivate func cancel(_ item: _Item) {
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
    private func dequeueNextItem() -> _Item? {
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

    private func perform(_ item: _Item) {
        activeTaskCount += 1
        item.task = Task { @ImagePipelineActor in
            await item.work()
            item.task = nil // just in case
            self.activeTaskCount -= 1
            self.performSchduledWork()
        }
    }

    /// - warning: For testing purposes only.
    func wait() async {
        if activeTaskCount == 0 { return }
        await withUnsafeContinuation { completion = $0 }
    }

    /// - note: You don't need to hold to it. This indirection exists purely to
    /// ensure that it never leads to retain cycles.
    @ImagePipelineActor struct Item {
        fileprivate weak var item: _Item?

        func setPriority(_ priority: TaskPriority) {
            item.map { $0.queue?.setPriority(priority, for: $0) }
        }

        func cancel() {
            item.map { $0.queue?.cancel($0) }
        }
    }

    /// A handle that can be used to change the priority of the pending work.
    @ImagePipelineActor
    final class _Item {
        let work: @ImagePipelineActor () async -> Void
        var priority: TaskPriority
        weak var node: LinkedList<_Item>.Node?
        var task: Task<Void, Never>?
        weak var queue: WorkQueue?

        init(priority: TaskPriority, work: @ImagePipelineActor @escaping () async -> Void) {
            self.priority = priority
            self.work = work
        }
    }

    /// - warning: For testing purposes.
    @ImagePipelineActor
    enum Event {
        case workAdded(_Item)
    }

    private struct ScheduledWork {
        let veryLow = LinkedList<_Item>()
        let low = LinkedList<_Item>()
        let normal = LinkedList<_Item>()
        let high = LinkedList<_Item>()
        let veryHigh = LinkedList<_Item>()

        func list(for priority: TaskPriority) -> LinkedList<_Item> {
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
