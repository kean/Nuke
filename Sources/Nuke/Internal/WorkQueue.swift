// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Combine

@ImagePipelineActor
final class WorkQueue {
    /// Sets the maximum number of concurrently executed operations.
    public nonisolated var maxConcurrentTaskCount: Int {
        get { _maxConcurrentTaskCount.value }
        set { _maxConcurrentTaskCount.value = newValue }
    }
    private let _maxConcurrentTaskCount: Mutex<Int>

    private var schedule = ScheduledWork()
    private var activeTaskCount = 0
    private var completion: UnsafeContinuation<Void, Never>?

    /// Setting this property to true prevents the queue from starting any queued
    /// tasks, but already executing tasks continue to execute.
    var isSuspended = false {
        didSet {
            guard oldValue != isSuspended, !isSuspended else { return }
            performSchduledWork()
        }
    }

    var onEvent: (@ImagePipelineActor (Event) -> Void)?

    nonisolated init(maxConcurrentTaskCount: Int = 1) {
        self._maxConcurrentTaskCount = Mutex(maxConcurrentTaskCount)
    }

    @discardableResult
    func add(priority: TaskPriority = .normal, work: @escaping () async -> Void) -> Operation {
        let operation = Operation(priority: priority, work: work)
        operation.queue = self
        if !isSuspended && activeTaskCount < maxConcurrentTaskCount {
            perform(operation)
        } else {
            let node = LinkedList<Operation>.Node(operation)
            operation.node = node
            schedule.list(for: operation.priority).prepend(node)
        }
        onEvent?(.added(operation))
        return operation
    }

    // MARK: - Managing Scheduled Operations

    fileprivate func operation(_ operation: Operation, didUpdatePriority newPriority: TaskPriority, oldPriority: TaskPriority) {
        guard let node = operation.node else { return /* Already executing */ }
        // Moving nodes between queues does not require new allocations
        schedule.list(for: oldPriority).remove(node)
        schedule.list(for: newPriority).prepend(node)
        onEvent?(.priorityUpdated(operation, newPriority))
    }

    fileprivate func cancel(_ operation: Operation) {
        if let node = operation.node {
            schedule.list(for: operation.priority).remove(node)
        }
        operation.task?.cancel()
        operation.node = nil
        operation.task = nil
        operation.queue = nil
        onEvent?(.cancelled(operation))
    }

    // MARK: - Performing Scheduled Work

    /// Returns a pending task with a highest priority.
    private func dequeueNextOperation() -> Operation? {
        for list in schedule.all {
            if let node = list.popLast() {
                node.value.node = nil
                return node.value
            }
        }
        return nil
    }

    private func performSchduledWork() {
        while !isSuspended, activeTaskCount < maxConcurrentTaskCount, let operation = dequeueNextOperation() {
            perform(operation)
        }
        if activeTaskCount == 0 {
            completion?.resume()
            completion = nil
        }
    }

    private func perform(_ operation: Operation) {
        activeTaskCount += 1
        operation.task = Task {
            await operation.work()
            operation.task = nil // just in case
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
    final class Operation {
        var priority: TaskPriority {
            didSet {
                guard oldValue != priority else { return }
                queue?.operation(self, didUpdatePriority: priority, oldPriority: oldValue)
            }
        }

        fileprivate let work: () async -> Void
        fileprivate weak var node: LinkedList<Operation>.Node?
        fileprivate var task: Task<Void, Never>?
        fileprivate weak var queue: WorkQueue?

        fileprivate init(priority: TaskPriority, work: @escaping () async -> Void) {
            self.priority = priority
            self.work = work
        }

        func cancel() {
            queue?.cancel(self)
        }
    }

    /// - warning: For testing purposes.
    @ImagePipelineActor
    enum Event {
        case added(Operation)
        case priorityUpdated(Operation, TaskPriority)
        case cancelled(Operation)
    }

    private struct ScheduledWork {
        let veryLow = LinkedList<Operation>()
        let low = LinkedList<Operation>()
        let normal = LinkedList<Operation>()
        let high = LinkedList<Operation>()
        let veryHigh = LinkedList<Operation>()

        func list(for priority: TaskPriority) -> LinkedList<Operation> {
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
