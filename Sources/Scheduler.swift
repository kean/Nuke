// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: Scheduler

/// Schedules execution of synchronous work.
public protocol Scheduler {
    func execute(token: CancellationToken?, closure: (Void) -> Void)
}

/// Schedules execution of asynchronous work which is considered
/// finished when `finish` closure is called.
public protocol AsyncScheduler {
    func execute(token: CancellationToken?, closure: (finish: (Void) -> Void) -> Void)
}

// MARK: - QueueScheduler

public class QueueScheduler: AsyncScheduler, Scheduler {
    public let queue: OperationQueue
    
    public convenience init(maxConcurrentOperationCount: Int) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = maxConcurrentOperationCount
        self.init(queue: queue)
    }
    
    public init(queue: OperationQueue) {
        self.queue = queue
    }
    
    public func execute(token: CancellationToken?, closure: (Void) -> Void) {
        self.execute(token: token) { (finish: (Void) -> Void) in
            closure()
            finish()
        }
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
            DispatchQueue.global().async {
                self.starter() { [weak self] in self?.finish() }
            }
        }
    }
    
    private func finish() {
        queue.sync {
            if !isFinished {
                isExecuting = false
                isFinished = true
            }
        }
    }
}
