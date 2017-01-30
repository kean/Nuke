// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: Scheduler

/// Schedules execution of the given closures.
public protocol Scheduler {
    /// Schedules execution of the given closure.
    func execute(token: CancellationToken?, closure: @escaping (Void) -> Void)
}

/// Schedules execution of asynchronous work which is considered
/// finished when `finish` closure is called.
public protocol AsyncScheduler {
    /// Schedules execution of asynchronous work which is considered
    /// finished when `finish` closure is called.
    func execute(token: CancellationToken?, closure: @escaping (_ finish: @escaping (Void) -> Void) -> Void)
}

// MARK: - DispatchQueueScheduler

/// A scheduler that executes work on the underlying `DispatchQueue`.
public final class DispatchQueueScheduler: Scheduler {
    public let queue: DispatchQueue
    
    /// Initializes the `DispatchQueueScheduler` with the given queue.
    public init(queue: DispatchQueue) {
        self.queue = queue
    }

    /// Executes the given closure asynchronously on the underlying queue.
    /// The scheduler automatically reacts to the token cancellation.
    public func execute(token: CancellationToken?, closure: @escaping (Void) -> Void) {
        if token?.isCancelling == true {
            return
        }
        let work = DispatchWorkItem(block: closure)
        queue.async(execute: work)
        token?.register { [weak work] in
            work?.cancel()
        }
    }
}

// MARK: - OperationQueueScheduler

/// A scheduler that executes work on the underlying `OperationQueue`.
public final class OperationQueueScheduler: AsyncScheduler {
    public let queue: OperationQueue

    /// Initializes the `OperationQueueScheduler` with the queue created
    /// with the given `maxConcurrentOperationCount`.
    public convenience init(maxConcurrentOperationCount: Int) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = maxConcurrentOperationCount
        self.init(queue: queue)
    }

    /// Initializes the `OperationQueueScheduler` with the given queue.
    public init(queue: OperationQueue) {
        self.queue = queue
    }

    /// Executes the given closure asynchronously  on the underlying queue by
    /// by wrapping the closure in the asynchronous operation. The operations
    /// gets finished when the given `finish` closure is called.
    /// The scheduler automatically reacts to the token cancellation.
    public func execute(token: CancellationToken?, closure: @escaping (_ finish: @escaping (Void) -> Void) -> Void) {
        if token?.isCancelling == true {
            return
        }
        let operation = Operation(starter: closure)
        queue.addOperation(operation)
        token?.register { [weak operation] in
            operation?.cancel()
        }
    }
}

// MARK: Operation

private final class Operation: Foundation.Operation {
    override var isExecuting: Bool {
        get { return _isExecuting }
        set {
            willChangeValue(forKey: "isExecuting")
            _isExecuting = newValue
            didChangeValue(forKey: "isExecuting")
        }
    }
    private var _isExecuting = false
    
    override var isFinished: Bool {
        get { return _isFinished }
        set {
            willChangeValue(forKey: "isFinished")
            _isFinished = newValue
            didChangeValue(forKey: "isFinished")
        }
    }
    var _isFinished = false
    
    let starter: (_ finish: @escaping (Void) -> Void) -> Void
    let queue = DispatchQueue(label: "com.github.kean.Nuke.Operation")
        
    init(starter: @escaping (_ fulfill: @escaping (Void) -> Void) -> Void) {
        self.starter = starter
    }
    
    override func start() {
        queue.sync {
            isExecuting = true
            DispatchQueue.global().async {
                self.starter() { [weak self] in
                    self?.finish()
                }
            }
        }
    }
    
    func finish() {
        queue.sync {
            if !isFinished {
                isExecuting = false
                isFinished = true
            }
        }
    }
}

// MARK: RateLimiter

/// Controls the rate at which the underlying scheduler executes work. Uses
/// classic [token bucket](https://en.wikipedia.org/wiki/Token_bucket) algorithm.
///
/// The main use case for rate limiter is to support large (infinite) collections
/// of images by preventing trashing of underlying systems, primary URLSession.
///
/// The implementation supports quick bursts of requests which can be executed
/// without any delays when "the bucket is full". This is important to prevent
/// rate limiter from affecting "normal" requests flow.
public final class RateLimiter: AsyncScheduler {
    private let scheduler: AsyncScheduler // underlying scheduler
    
    private let burst: Double
    private let burstInterval: TimeInterval
    private var bucket: Double
    private var lastRefill: TimeInterval
    
    private var isExecutingPendingItems = false
    private var pendingItems = [Item]()
    
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.RateLimiter")
    
    private struct Item {
        let token: CancellationToken?
        let closure: (@escaping (Void) -> Void) -> Void
    }
    
    /// Initializes the `RateLimiter` with the given scheduler and configuration.
    /// - parameter scheduler: Underlying scheduler which `RateLimiter` uses
    /// to execute items.
    /// - parameter rate: Maximum number of requests per second. 30 by default.
    /// - parameter burst: Maximum number of requests which can be executed without
    /// any delays when "bucket is full". 15 by default.
    public init(scheduler: AsyncScheduler, rate: Int = 30, burst: Int = 15) {
        self.scheduler = scheduler
        self.burst = Double(burst)
        self.burstInterval = Double(burst) / Double(rate)
        self.bucket = Double(burst)
        self.lastRefill = CFAbsoluteTimeGetCurrent()
    }
    
    public func execute(token: CancellationToken?, closure: @escaping (@escaping (Void) -> Void) -> Void) {
        if token?.isCancelling == true { // Quick pre-lock check
            return
        }
        queue.sync {
            if !pendingItems.isEmpty || !execute(token: token, closure: closure) {
                // `pending` is a queue: insert at 0; popLast() later
                pendingItems.insert(Item(token: token, closure: closure), at: 0)
                setNeedsExecutePendingItems()
            }
        }
    }
    
    private func execute(token: CancellationToken?, closure: @escaping (@escaping (Void) -> Void) -> Void) -> Bool {
        // Drop cancelled items before they get to the bucket
        if token?.isCancelling == true {
            return true
        }
        
        refillBucket()
        if bucket < 1.0 {
            return false // Bucket is empty
        }
        
        // Execute an item
        bucket -= 1.0
        scheduler.execute(token: token, closure: closure)
        return true
    }
    
    private func refillBucket() {
        let now = CFAbsoluteTimeGetCurrent()
        bucket += (now - lastRefill) * (burst / burstInterval) // passed time * rate
        lastRefill = now
        if bucket > burst { // Prevent bucket overflow
            bucket = burst
        }
    }
    
    private func setNeedsExecutePendingItems() {
        guard !isExecutingPendingItems else { return }
        isExecutingPendingItems = true
        queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.executePendingItems()
        }
    }
    
    private func executePendingItems() {
        while let item = pendingItems.popLast() {
            if !execute(token: item.token, closure: item.closure) {
                pendingItems.append(item) // Put the item back
                break // Stop executing items
            }
        }
        isExecutingPendingItems = false
        if !pendingItems.isEmpty {
            setNeedsExecutePendingItems()
        }
    }
}
