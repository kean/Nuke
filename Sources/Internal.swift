// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - Lock

extension NSLock {
    func sync<T>(_ closure: () -> T) -> T {
        lock(); defer { unlock() }
        return closure()
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
    private let queue: DispatchQueue
    private var pending = LinkedList<Task>() // fast append, fast remove first
    private var isExecutingPendingTasks = false

    private typealias Task = (CancellationToken, () -> Void)

    /// Initializes the `RateLimiter` with the given configuration.
    /// - parameter queue: Queue on which to execute pending tasks.
    /// - parameter rate: Maximum number of requests per second. 80 by default.
    /// - parameter burst: Maximum number of requests which can be executed without
    /// any delays when "bucket is full". 25 by default.
    internal init(queue: DispatchQueue, rate: Int = 80, burst: Int = 25) {
        self.queue = queue
        self.bucket = TokenBucket(rate: Double(rate), burst: Double(burst))
    }

    internal func execute(token: CancellationToken, _ closure: @escaping () -> Void) {
        let task = Task(token, closure)
        if !pending.isEmpty || !_execute(task) {
            pending.append(task)
            _setNeedsExecutePendingTasks()
        }
    }

    private func _execute(_ task: Task) -> Bool {
        guard !task.0.isCancelling else {
            return true // No need to execute
        }
        return bucket.execute(task.1)
    }

    private func _setNeedsExecutePendingTasks() {
        guard !isExecutingPendingTasks else { return }
        isExecutingPendingTasks = true
        // Compute a delay such that by the time the closure is executed the
        // bucket is refilled to a point that is able to execute at least one
        // pending task. With a rate of 100 tasks we expect a refill every 10 ms.
        let delay = Int(1.15 * (1000 / bucket.rate)) // 14 ms for rate 80 (default)
        let bounds = max(100, min(5, delay)) // Make the delay is reasonable
        queue.asyncAfter(deadline: .now() + .milliseconds(bounds), execute: _executePendingTasks)
    }

    private func _executePendingTasks() {
        while let node = pending.first, _execute(node.value) {
            pending.remove(node)
        }
        isExecutingPendingTasks = false
        if !pending.isEmpty { // Not all pending items were executed
            _setNeedsExecutePendingTasks()
        }
    }

    private final class TokenBucket {
        let rate: Double
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

// MARK: - Operation

internal final class Operation: Foundation.Operation {
    enum State { case executing, finished }

    // `queue` here is basically to make TSan happy. In reality the calls to
    // `_setState` are guaranteed to never run concurrently in different ways.
    private var _state: State?
    private func _setState(_ newState: State) {
        willChangeValue(forKey: "isExecuting")
        if newState == .finished {
            willChangeValue(forKey: "isFinished")
        }
        queue.sync(flags: .barrier) {
            _state = newState
        }
        didChangeValue(forKey: "isExecuting")
        if newState == .finished {
            didChangeValue(forKey: "isFinished")
        }
    }

    override var isExecuting: Bool {
        return queue.sync { _state == .executing }
    }
    override var isFinished: Bool {
        return queue.sync { _state == .finished }
    }

    typealias Starter = (_ fulfill: @escaping () -> Void) -> Void
    private let starter: Starter
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Operation", attributes: .concurrent)

    init(starter: @escaping Starter) {
        self.starter = starter
    }

    override func start() {
        guard !isCancelled else {
            _setState(.finished)
            return
        }
        _setState(.executing)
        starter { [weak self] in
            DispatchQueue.main.async { self?._finish() }
        }
    }

    // Calls to _finish() are syncrhonized on the main thread. This way we
    // guarantee that `starter` doesn't finish operation more than once.
    // Other paths are also guaranteed to be safe.
    private func _finish() {
        guard _state != .finished else { return }
        _setState(.finished)
    }
}

// MARK: - LinkedList

/// A doubly linked list.
internal final class LinkedList<Element> {
    // first <-> node <-> ... <-> last
    private(set) var first: Node?
    private(set) var last: Node?

    deinit {
        removeAll()
    }

    var isEmpty: Bool {
        return last == nil
    }

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
        if node === last {
            last = node.previous
        }
        if node === first {
            first = node.next
        }
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

        init(value: Element) {
            self.value = value
        }
    }
}

// MARK: - DataBuffer

/// Buffer optimized for non-progressive requests. We keep chunks separately as
/// the arreive. Those same chunks are stored as resumable data in `DataLoader`.
/// We combine the chunks once when all data is loaded.
/// P.S. Might be doing something stupid here, need to profile - in theory it
/// all checks out.
internal final class DataBuffer {
    private let isProgressive: Bool
    private lazy var chunks = [Data]()
    private lazy var buffer = Data()

    init(isProgressive: Bool) {
        self.isProgressive = isProgressive
    }

    func append(_ data: Data) {
        isProgressive ? buffer.append(data) : chunks.append(data)
    }

    var data: Data {
        if isProgressive {
            return self.buffer
        }
        if chunks.count == 1 { // Micro optimization when image from cache / small
            return chunks[0]
        }
        let count = chunks.reduce(0, { $0 + $1.count })
        var buffer = Data(capacity: count)
        for chunk in chunks {
            buffer.append(chunk)
        }
        return buffer
    }
}

// MARK: - Misc

internal func _now() -> TimeInterval {
    return CFAbsoluteTimeGetCurrent()
}
