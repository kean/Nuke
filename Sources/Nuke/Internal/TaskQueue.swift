// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A priority-aware, concurrency-limited work queue that runs on `@ImagePipelineActor`.
///
/// `TaskQueue` manages a configurable number of concurrent operations, each backed
/// by a Swift `Task`. Pending operations are stored in per-priority buckets so the
/// highest-priority work is always dequeued first (FIFO within the same priority).
@ImagePipelineActor
public final class TaskQueue: Sendable {
    var runningCount = 0
    var pendingCount = 0
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
        get { _isSuspended.value }
        set {
            if _isSuspended.testAndSet(newValue), !newValue {
                Task { @ImagePipelineActor in drain() }
            }
        }
    }

    /// The default value matches the number of cores on the machine. For
    /// operations like image processing, it's recommended to use a lower number
    /// to avoid fully saturating the CPU.
    nonisolated public var maxConcurrentOperationCount: Int {
        get { _maxConcurrentOperationCount.value }
        set {
            let oldValue = _maxConcurrentOperationCount.withLock {
                let old = $0; $0 = newValue; return old
            }
            if newValue > oldValue {
                Task { @ImagePipelineActor in drain() }
            }
        }
    }

    nonisolated private let _maxConcurrentOperationCount: Mutex<Int>
    nonisolated private let _isSuspended = Mutex(value: false)

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
    nonisolated public init(maxConcurrentOperationCount: Int = ProcessInfo.processInfo.processorCount) {
        self._maxConcurrentOperationCount = Mutex(value: maxConcurrentOperationCount)
    }

    /// Adds work to the queue. The closure runs `@ImagePipelineActor`. The
    /// concurrency slot is freed when the closure returns.
    ///
    /// If the work needs to be performed in a background, the caller needs to
    /// ensure that happens.
    @discardableResult
    func add(_ work: @ImagePipelineActor @Sendable @escaping () async throws -> Void) -> TaskQueue.Operation {
        let operation = TaskQueue.Operation(queue: self)
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
        while !isSuspended && runningCount < maxConcurrentOperationCount && pendingCount > 0 {
            guard let operation = dequeueHighestPriority() else { break }
            execute(operation)
        }
    }

    private func dequeueHighestPriority() -> TaskQueue.Operation? {
        for i in stride(from: buckets.count - 1, through: 0, by: -1) {
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
        let work = operation.work
        operation.work = nil
        operation.task = Task { @ImagePipelineActor [weak self] in
            try? await work?()
            self?.operationFinished()
        }
    }

    fileprivate func operationFinished() {
        runningCount -= 1
        drain()
        onEvent?(.finished)
    }

    fileprivate func operationPriorityChanged(_ operation: TaskQueue.Operation, from oldPriority: TaskPriority) {
        guard let node = operation.node else { return }
        buckets[oldPriority.rawValue].remove(node)
        if operation.priority < oldPriority {
            buckets[operation.priority.rawValue].prepend(node)
        } else {
            buckets[operation.priority.rawValue].append(node)
        }
        onEvent?(.priorityChanged(operation))
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
        /// moves it to the corresponding priority bucket. Changes to a running
        /// or cancelled operation update the stored value but have no scheduling
        /// effect.
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
        fileprivate weak var node: LinkedList<TaskQueue.Operation>.Node?
        private weak let queue: TaskQueue?

        // Test hooks.
        var onCancelled: (() -> Void)?
        var onPriorityChanged: ((TaskPriority) -> Void)?

        init(queue: TaskQueue? = nil) {
            self.queue = queue
        }

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
