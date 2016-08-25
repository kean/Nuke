// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: Scheduler

/// Schedules execution of synchronous work.
public protocol Scheduler {
    func execute(token: CancellationToken?, closure: @escaping (Void) -> Void)
}

/// Schedules execution of asynchronous work which is considered
/// finished when `finish` closure is called.
public protocol AsyncScheduler {
    func execute(token: CancellationToken?, closure: @escaping (_ finish: @escaping (Void) -> Void) -> Void)
}

// MARK: - DispatchQueueScheduler

internal final class DispatchQueueScheduler: Scheduler {
    private let queue: DispatchQueue
    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func execute(token: CancellationToken?, closure: @escaping (Void) -> Void) {
        if let token = token, token.isCancelling { return }
        let work = DispatchWorkItem(block: closure)
        queue.async(execute: work)
        token?.register { work.cancel() }
    }
}

// MARK: - OperationQueueScheduler

public final class OperationQueueScheduler: AsyncScheduler {
    public let queue: OperationQueue

    public convenience init(maxConcurrentOperationCount: Int) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = maxConcurrentOperationCount
        self.init(queue: queue)
    }

    public init(queue: OperationQueue) {
        self.queue = queue
    }

    public func execute(token: CancellationToken?, closure: @escaping (_ finish: @escaping (Void) -> Void) -> Void) {
        if let token = token, token.isCancelling { return }
        let operation = Operation(starter: closure)
        queue.addOperation(operation)
        token?.register { operation.cancel() }
    }
}

// MARK: Operation

private final class Operation: Foundation.Operation {
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
    var _isFinished = false
    
    let starter: (_ finish: @escaping (Void) -> Void) -> Void
    let queue = DispatchQueue(label: "\(domain).Operation")
    
    init(starter: @escaping (_ fulfill: @escaping (Void) -> Void) -> Void) {
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
    
    func finish() {
        queue.sync {
            if !isFinished {
                isExecuting = false
                isFinished = true
            }
        }
    }
}
