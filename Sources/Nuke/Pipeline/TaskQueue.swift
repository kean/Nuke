// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

/// A priority-aware, concurrency-limited work queue that runs on `@ImagePipelineActor`.
///
/// `TaskQueue` manages a configurable number of concurrent operations, each backed
/// by a Swift `Task`. Pending operations are stored in per-priority buckets so the
/// highest-priority work is always dequeued first (FIFO within the same priority).
@ImagePipelineActor
public final class TaskQueue: Sendable {
    var runningCount = 0
    var pendingCount = 0
    private var runningLowPriorityCount = 0
    private let buckets = (0..<TaskPriority.allCases.count).map { _ in LinkedList<TaskQueue.Operation>() }

    /// Controls whether the queue drains pending work.
    ///
    /// Setting to `true` prevents new work from starting. Already-running
    /// operations continue to completion. Setting back to `false` resumes
    /// draining from any context.
    ///
    /// Concurrency-safe: concurrent resume calls each spawn a Task on
    /// `@ImagePipelineActor`, where `drain()` serializes. Double-drains are
    /// no-ops because the loop condition checks counts.
    nonisolated public var isSuspended: Bool {
        get { _isSuspended.withLock { $0 } }
        set {
            let didChange = _isSuspended.withLock {
                guard $0 != newValue else { return false }
                $0 = newValue
                return true
            }
            if didChange, !newValue {
                Task { @ImagePipelineActor in drain() }
            }
        }
    }

    /// The default value matches the number of cores on the machine. For
    /// operations like image processing, it's recommended to use a lower number
    /// to avoid fully saturating the CPU.
    nonisolated public var maxConcurrentTaskCount: Int {
        get { _limits.withLock { $0.maxConcurrentTaskCount } }
        set {
            let oldValue = _limits.withLock {
                let old = $0.maxConcurrentTaskCount; $0.maxConcurrentTaskCount = newValue; return old
            }
            if newValue > oldValue {
                Task { @ImagePipelineActor in drain() }
            }
        }
    }

    /// The number of slots that the work with a priority lower than `.normal`,
    /// such as prefetching, can't take, so that the work added at a higher
    /// priority finds a free slot even when there is more low-priority work
    /// than slots. The low-priority work always gets at least one slot.
    ///
    /// The work counts by its current priority: raising the priority of a
    /// running task frees its low-priority slot. `0` by default.
    nonisolated public var reservedTaskCount: Int {
        get { _limits.withLock { $0.reservedTaskCount } }
        set {
            let oldValue = _limits.withLock {
                let old = $0.reservedTaskCount; $0.reservedTaskCount = newValue; return old
            }
            if newValue < oldValue {
                Task { @ImagePipelineActor in drain() }
            }
        }
    }

    private struct Limits: Sendable {
        var maxConcurrentTaskCount: Int
        var reservedTaskCount: Int
    }

    nonisolated private let _limits: OSAllocatedUnfairLock<Limits>
    nonisolated private let _isSuspended = OSAllocatedUnfairLock(initialState: false)

    /// Events emitted by the queue for observation (testing only).
    enum Event {
        case enqueued(TaskQueue.Operation)
        case finished
        case cancelled(TaskQueue.Operation)
        case priorityChanged(TaskQueue.Operation)
    }

    /// Test hook.
    var onEvent: ((Event) -> Void)?

    /// Initializes the queue.
    nonisolated public init(maxConcurrentTaskCount: Int = ProcessInfo.processInfo.processorCount) {
        self._limits = OSAllocatedUnfairLock(initialState: Limits(maxConcurrentTaskCount: maxConcurrentTaskCount, reservedTaskCount: 0))
    }

    /// Initializes the queue.
    ///
    /// - parameters:
    ///   - maxConcurrentTaskCount: The maximum number of tasks that run at the same time.
    ///   - reservedTaskCount: The number of slots that the work with a priority
    ///     lower than `.normal` can't take. See ``reservedTaskCount``.
    nonisolated public init(maxConcurrentTaskCount: Int, reservedTaskCount: Int) {
        self._limits = OSAllocatedUnfairLock(initialState: Limits(maxConcurrentTaskCount: maxConcurrentTaskCount, reservedTaskCount: reservedTaskCount))
    }

    /// Adds work to the queue. The closure runs `@ImagePipelineActor`. The
    /// concurrency slot is freed when the closure returns.
    ///
    /// The priority is passed here rather than set on the returned operation
    /// because the work can start right away, and the priority decides whether
    /// it may take a reserved slot.
    ///
    /// If the work needs to be performed in a background, the caller needs to
    /// ensure that happens.
    @discardableResult
    func add(priority: TaskPriority = .normal, _ work: @ImagePipelineActor @Sendable @escaping () async throws -> Void) -> TaskQueue.Operation {
        let operation = TaskQueue.Operation(queue: self, priority: priority)
        operation.work = work
        enqueue(operation)
        return operation
    }

    // MARK: - Private

    private func enqueue(_ operation: TaskQueue.Operation) {
        operation.node = buckets[operation.priority.rawValue].append(operation)
        pendingCount += 1
        onEvent?(.enqueued(operation))
        drain()
    }

    private func drain() {
        guard !isSuspended else { return }
        // The limits are settable from any thread, so every read takes a lock.
        // Read them once: a limit raised mid-drain schedules a drain of its own,
        // and one lowered mid-drain is no different from one lowered right after.
        let limits = _limits.withLock { $0 }
        let lowPriorityLimit = max(1, limits.maxConcurrentTaskCount - limits.reservedTaskCount)
        while runningCount < limits.maxConcurrentTaskCount && pendingCount > 0 {
            guard let operation = dequeueHighestPriority(isLowPriorityAllowed: runningLowPriorityCount < lowPriorityLimit) else { break }
            execute(operation)
        }
    }

    private func dequeueHighestPriority(isLowPriorityAllowed: Bool) -> TaskQueue.Operation? {
        let lowest = isLowPriorityAllowed ? 0 : TaskPriority.normal.rawValue
        for i in stride(from: buckets.count - 1, through: lowest, by: -1) {
            if let node = buckets[i].first {
                buckets[i].remove(node)
                node.value.node = nil
                pendingCount -= 1
                return node.value
            }
        }
        return nil
    }

    private func execute(_ operation: TaskQueue.Operation) {
        runningCount += 1
        if operation.priority < .normal {
            operation.isRunningAsLowPriority = true
            runningLowPriorityCount += 1
        }
        // The operation is captured strongly to keep it alive while it executes:
        // it is no longer stored in the pending buckets and the clients typically
        // reference it weakly. The work is read _inside_ the task (instead of
        // being hoisted out of the operation) so that cancelling an operation
        // that was dequeued, but hasn't started yet, prevents it from running.
        operation.task = Task { @ImagePipelineActor [weak self] in
            if let work = operation.work {
                operation.work = nil
                try? await work()
            }
            operation.task = nil // Break the retain cycle
            self?.operationFinished(operation)
        }
    }

    fileprivate func operationFinished(_ operation: TaskQueue.Operation) {
        runningCount -= 1
        if operation.isRunningAsLowPriority {
            operation.isRunningAsLowPriority = false
            runningLowPriorityCount -= 1
        }
        drain()
        onEvent?(.finished)
    }

    fileprivate func operationPriorityChanged(_ operation: TaskQueue.Operation, from oldPriority: TaskPriority) {
        guard let node = operation.node else {
            // A running operation moves in or out of the low-priority slots.
            let isLowPriority = operation.priority < .normal
            if operation.task != nil, operation.isRunningAsLowPriority != isLowPriority {
                operation.isRunningAsLowPriority = isLowPriority
                runningLowPriorityCount += isLowPriority ? 1 : -1
                if !isLowPriority { drain() }
            }
            return
        }
        buckets[oldPriority.rawValue].remove(node)
        if operation.priority < oldPriority {
            buckets[operation.priority.rawValue].prepend(node)
        } else {
            buckets[operation.priority.rawValue].append(node)
        }
        onEvent?(.priorityChanged(operation))
        // The work that is no longer low-priority can take a reserved slot.
        if oldPriority < .normal && operation.priority >= .normal {
            drain()
        }
    }

    fileprivate func operationCancelled(_ operation: TaskQueue.Operation) {
        guard let node = operation.node else { return }
        buckets[operation.priority.rawValue].remove(node)
        operation.node = nil
        pendingCount -= 1
        onEvent?(.cancelled(operation))
    }

    /// A handle to a unit of work enqueued in a ``TaskQueue``.
    ///
    /// Use the handle to adjust ``priority`` or ``cancel()`` the operation.
    /// Priority changes move the operation between the queue's internal buckets;
    /// cancellation removes it from the queue and cancels the underlying `Task`.
    @ImagePipelineActor
    final class Operation: Sendable {
        /// The scheduling priority. Changing this while the operation is pending
        /// moves it to the corresponding priority bucket. Changing it while the
        /// operation runs decides whether it counts toward the slots of the
        /// low-priority work. Changes to a cancelled operation have no effect.
        var priority: TaskPriority = .normal {
            didSet {
                guard oldValue != priority else { return }
                queue?.operationPriorityChanged(self, from: oldValue)
                onPriorityChanged?(priority)
            }
        }

        fileprivate var work: (@ImagePipelineActor @Sendable () async throws -> Void)?
        private(set) var isCancelled = false
        fileprivate var task: Task<Void, Never>?
        fileprivate var isRunningAsLowPriority = false
        fileprivate weak var node: LinkedList<TaskQueue.Operation>.Node?
        private weak var queue: TaskQueue?

        // Test hooks.
        var onCancelled: (() -> Void)?
        var onPriorityChanged: ((TaskPriority) -> Void)?

        init(queue: TaskQueue? = nil, priority: TaskPriority = .normal) {
            self.queue = queue
            self.priority = priority
        }

        /// Cancels the operation. If the work hasn't started executing yet, it
        /// never runs; otherwise, the underlying task is cancelled.
        func cancel() {
            guard !isCancelled else { return }
            isCancelled = true
            work = nil
            task?.cancel()
            queue?.operationCancelled(self)
            onCancelled?()
        }
    }
}

// MARK: - TaskQueue (Deprecated)

extension TaskQueue {
    /// The maximum number of concurrently running tasks.
    ///
    /// - warning: Deprecated in Nuke 14.0. Use ``maxConcurrentTaskCount`` instead.
    @available(*, deprecated, renamed: "maxConcurrentTaskCount", message: "Deprecated in Nuke 14.0. The queue no longer has operations behind it. Use `maxConcurrentTaskCount` instead.")
    nonisolated public var maxConcurrentOperationCount: Int {
        get { maxConcurrentTaskCount }
        set { maxConcurrentTaskCount = newValue }
    }

    /// Initializes the queue.
    ///
    /// - warning: Deprecated in Nuke 14.0. Use ``init(maxConcurrentTaskCount:)`` instead.
    @available(*, deprecated, renamed: "init(maxConcurrentTaskCount:)", message: "Deprecated in Nuke 14.0. The queue no longer has operations behind it. Use `init(maxConcurrentTaskCount:)` instead.")
    nonisolated public convenience init(maxConcurrentOperationCount: Int) {
        self.init(maxConcurrentTaskCount: maxConcurrentOperationCount)
    }
}
