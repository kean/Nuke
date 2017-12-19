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

// MARK: - Extensions

internal extension DispatchQueue {
    func execute(token: CancellationToken, closure: @escaping () -> Void) {
        guard !token.isCancelling else { return } // fast preflight check
        let work = DispatchWorkItem(block: closure)
        async(execute: work)
        token.register { [weak work] in work?.cancel() }
    }
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
    /// - parameter rate: Maximum number of requests per second. 45 by default.
    /// - parameter burst: Maximum number of requests which can be executed without
    /// any delays when "bucket is full". 15 by default.
    internal init(rate: Int = 45, burst: Int = 15) {
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
        return bucket.execute { task.1() }
    }

    private func _setNeedsExecutePendingTasks() {
        guard !isExecutingPendingTasks else { return }
        isExecutingPendingTasks = true
        queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?._executePendingTasks()
        }
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
        init(rate: Double = 30.0, burst: Double = 15.0) {
            self.rate = rate
            self.burst = burst
            self.bucket = burst
            self.timestamp = CFAbsoluteTimeGetCurrent()
        }

        /// Returns `true` if the closure was executed, `false` if dropped.
        func execute(closure: () -> Void) -> Bool {
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

/// Limits number of maximum concurrent tasks.
internal final class TaskQueue {
    // An alternative of using custom Foundation.Operation requires more code,
    // less performant and even harder to get right https://github.com/kean/Nuke/issues/141.
    private var executingTaskCount: Int = 0
    private var pendingTasks = LinkedList<Task>() // fast append, fast remove first
    private let maxConcurrentTaskCount: Int
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.TaskQueue")

    internal typealias Work = (_ finish: @escaping () -> Void) -> Void
    private typealias Task = (CancellationToken, Work)

    internal init(maxConcurrentTaskCount: Int) {
        self.maxConcurrentTaskCount = maxConcurrentTaskCount
    }

    internal func execute(token: CancellationToken, _ closure: @escaping Work) {
        queue.async {
            guard !token.isCancelling else { return } // fast preflight check
            self.pendingTasks.append((token, closure))
            self._executeTasksIfNecessary()
        }
    }

    private func _executeTasksIfNecessary() {
        while executingTaskCount < maxConcurrentTaskCount, let first = pendingTasks.first {
            pendingTasks.remove(first)
            _executeTask(first.value)
        }
    }

    private func _executeTask(_ task: Task) {
        guard !task.0.isCancelling else { return } // check if still not cancelled
        executingTaskCount += 1
        var isFinished = false
        task.1 { [weak self] in
            self?.queue.async {
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

// MARK: - Bag

/// Lightweight unordered data structure for storing a small number of elements.
/// The idea is that it doesn't allocate any space on heap during initialization
/// and it inlines first couple of elements and only then falls back to array
/// (`ContiguousArray`) backed storage.
///
/// The name `Bag` (`Multiset`) is actually taken and it means something
/// different than what this type does. But since it's an internal type it
/// should work for now.
internal struct Bag<Element>: Sequence {
    private var first: Element? // inline first couple of elements
    private var second: Element?
    // ~20% faster than Array based on perf tests
    private var remaining: ContiguousArray<Element>?

    mutating func insert(_ value: Element) {
        if first == nil { first = value }
        else if second == nil { second = value }
        else {
            // created lazily
            if remaining == nil { remaining = ContiguousArray<Element>() }
            remaining!.append(value)
        }
    }

    // MARK: Sequence

    internal struct BagIterator: IteratorProtocol {
        private var index = 0
        private var bag: Bag
        init(_ bag: Bag) { self.bag = bag }

        mutating func next() -> Element? {
            var element: Element?
            if index == 0 { element = bag.first }
            else if index == 1 { element = bag.second }
            else {
                if let remaining = bag.remaining, index - 2 < remaining.count {
                    element = remaining[index - 2]
                }
            }
            index += 1
            return element
        }
    }

    func makeIterator() -> BagIterator {
        return BagIterator(self)
    }
}
