// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: Scheduler

/// Schedules execution of asynchronous tasks.
public protocol Scheduler {
    func execute(token: CancellationToken?, closure: (finish: (Void) -> Void) -> Void)
}

public extension Scheduler {
    public func execute(token: CancellationToken?, closure: (Void) -> Void) {
        self.execute(token: token) { finish in
            closure()
            finish()
        }
    }
}

// MARK: - QueueScheduler

public class QueueScheduler: Scheduler {
    public let queue: OperationQueue
    
    public convenience init(maxConcurrentOperationCount: Int) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = maxConcurrentOperationCount
        self.init(queue: queue)
    }
    
    public init(queue: OperationQueue) {
        self.queue = queue
    }
    
    public func execute(token: CancellationToken?, closure: (finish: (Void) -> Void) -> Void) {
        if let token = token, token.isCancelling { return }
        let operation = Operation(starter: closure)
        token?.register { operation.cancel() }
        queue.addOperation(operation)
    }
}

// MARK: Operation

internal final class Operation: Foundation.Operation {
    override var isExecuting : Bool {
        get { return _isExecuting }
        set {
            willChangeValue(forKey: "isExecuting")
            _isExecuting = newValue
            didChangeValue(forKey: "isExecuting")
        }
    }
    private var _isExecuting = false
    
    override var isFinished : Bool {
        get { return _isFinished }
        set {
            willChangeValue(forKey: "isFinished")
            _isFinished = newValue
            didChangeValue(forKey: "isFinished")
        }
    }
    private var _isFinished = false
    
    private let starter: (finish: (Void) -> Void) -> Void
    private let queue = DispatchQueue(label: "\(domain).Operation")
    
    init(starter: (fulfill: (Void) -> Void) -> Void) {
        self.starter = starter
    }
    
    override func start() {
        queue.sync {
            isExecuting = true
            if isCancelled {
                finish()
            } else {
                starter() { [weak self] in
                    _ = self?.queue.async { self?.finish() }
                }
            }
        }
    }
    
    private func finish() {
        if !isFinished {
            isExecuting = false
            isFinished = true
        }
    }
    
    override func cancel() {
        queue.sync {
            if !isCancelled {
                super.cancel()
                if isExecuting {
                    finish()
                }
            }
        }
    }
}
