// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - Lock

internal final class Lock {
    var mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)

    init() { pthread_mutex_init(mutex, nil) }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deinitialize()
        mutex.deallocate(capacity: 1)
    }

    func sync<T>(_ closure: () -> T) -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return closure()
    }

    func lock() { pthread_mutex_lock(mutex) }

    func unlock() { pthread_mutex_unlock(mutex) }
}

// MARK: - RateLimiter

/// Controls the rate at which the work is executed. Uses the classic [token
/// bucket](https://en.wikipedia.org/wiki/Token_bucket) algorithm.
///
/// The main use case for rate limiter is to support large (infinite) collections
/// of images by preventing trashing of underlying systems, primary URLSession.
///
/// The implementation supports quick bursts of requests which can be executed
/// without any delays when "the bucket is full". This is important to prevent
/// rate limiter from affecting "normal" requests flow.
internal final class RateLimiter {
    private let bucket: TokenBucket
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.RateLimiter")
    private var pending = LinkedList<Task>() // fast append, fast remove first
    private var isExecutingPendingTasks = false

    private typealias Task = (CancellationToken, () -> Void)

    /// Initializes the `RateLimiter` with the given configuration.
    /// - parameter rate: Maximum number of requests per second. 100 by default.
    /// - parameter burst: Maximum number of requests which can be executed without
    /// any delays when "bucket is full". 30 by default.
    internal init(rate: Int = 100, burst: Int = 30) {
        self.bucket = TokenBucket(rate: Double(rate), burst: Double(burst))
    }

    internal func execute(token: CancellationToken, _ closure: @escaping () -> Void) {
        queue.sync {
            let task = Task(token, closure)
            if !pending.isEmpty || !_execute(task) {
                pending.append(task)
                _setNeedsExecutePendingTasks()
            }
        }
    }

    private func _execute(_ task: Task) -> Bool {
        guard !task.0.isCancelling else { return true } // no need to execute
        return bucket.execute(task.1)
    }

    private func _setNeedsExecutePendingTasks() {
        guard !isExecutingPendingTasks else { return }
        isExecutingPendingTasks = true
        queue.asyncAfter(deadline: .now() + 0.05, execute: _executePendingTasks)
    }

    private func _executePendingTasks() {
        while let node = pending.first, _execute(node.value) {
            pending.remove(node)
        }
        isExecutingPendingTasks = false
        if !pending.isEmpty { // not all pending items were executed
            _setNeedsExecutePendingTasks()
        }
    }

    private final class TokenBucket {
        private let rate: Double
        private let burst: Double // maximum bucket size
        private var bucket: Double
        private var timestamp: TimeInterval // last refill timestamp

        /// - parameter rate: Rate (tokens/second) at which bucket is refilled.
        /// - parameter burst: Bucket size (maximum number of tokens).
        init(rate: Double, burst: Double) {
            self.rate = rate
            self.burst = burst
            self.bucket = burst
            self.timestamp = CFAbsoluteTimeGetCurrent()
        }

        /// Returns `true` if the closure was executed, `false` if dropped.
        func execute(_ closure: () -> Void) -> Bool {
            refill()
            guard bucket >= 1.0 else {
                return false // bucket is empty
            }
            bucket -= 1.0
            closure()
            return true
        }

        private func refill() {
            let now = CFAbsoluteTimeGetCurrent()
            bucket += rate * max(0, now - timestamp) // rate * (time delta)
            timestamp = now
            if bucket > burst { // prevent bucket overflow
                bucket = burst
            }
        }
    }
}

// MARK: - TaskQueue

/// Limits number of maximum concurrent tasks. By default tasks are executed on
/// the underlying concurrent dispatch queue (with default options).
internal final class TaskQueue {
    // An alternative of using custom Foundation.Operation requires more code,
    // less performant and even harder to get right https://github.com/kean/Nuke/issues/141.
    private var executingTaskCount: Int = 0
    private var pendingTasks = LinkedList<Task>() // fast append, fast remove first
    private let maxConcurrentTaskCount: Int
    private let executionQueue = DispatchQueue(label: "com.github.kean.Nuke.TaskQueue.Execution", attributes: .concurrent)
    private let syncQueue = DispatchQueue(label: "com.github.kean.Nuke.TaskQueue.Sync")

    internal typealias Work = (_ finish: @escaping () -> Void) -> Void
    private typealias Task = (CancellationToken, Work)

    internal init(maxConcurrentTaskCount: Int) {
        self.maxConcurrentTaskCount = maxConcurrentTaskCount
    }

    internal func execute(token: CancellationToken, _ closure: @escaping Work) {
        syncQueue.async {
            guard !token.isCancelling else { return } // fast preflight check
            self.pendingTasks.append((token, closure))
            self._executeTasksIfNecessary()
        }
    }

    private func _executeTasksIfNecessary() {
        while executingTaskCount < maxConcurrentTaskCount, let node = pendingTasks.first {
            pendingTasks.remove(node)
            let task = node.value
            if !task.0.isCancelling { // check if still not cancelled
                executingTaskCount += 1 // only then execute
                executionQueue.async { self._executeTask(task) }
            }
        }
    }

    private func _executeTask(_ task: Task) {
        var isFinished = false
        task.1 { [weak self] in
            self?.syncQueue.async {
                guard !isFinished else { return } // finish called twice
                isFinished = true
                self?.executingTaskCount -= 1
                self?._executeTasksIfNecessary()
            }
        }
    }
}

// MARK: - LinkedList

/// A doubly linked list.
internal final class LinkedList<Element> {
    // first <-> node <-> ... <-> last
    private(set) var first: Node?
    private(set) var last: Node?

    deinit { removeAll() } // only available on classes

    var isEmpty: Bool { return last == nil }

    /// Adds an element to the end of the list.
    @discardableResult func append(_ element: Element) -> Node {
        let node = Node(value: element)
        append(node)
        return node
    }

    /// Adds a node to the end of the list.
    func append(_ node: Node) {
        if let last = last {
            last.next = node
            node.previous = last
            self.last = node
        } else {
            last = node
            first = node
        }
    }

    func remove(_ node: Node) {
        node.next?.previous = node.previous // node.previous is nil if node=first
        node.previous?.next = node.next // node.next is nil if node=last
        if node === last { last = node.previous }
        if node === first { first = node.next }
        node.next = nil
        node.previous = nil
    }

    func removeAll() {
        // avoid recursive Nodes deallocation
        var node = first
        while let next = node?.next {
            node?.next = nil
            next.previous = nil
            node = next
        }
        last = nil
        first = nil
    }

    final class Node {
        let value: Element
        fileprivate var next: Node?
        fileprivate var previous: Node?

        init(value: Element) { self.value = value }
    }
}
