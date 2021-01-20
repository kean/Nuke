// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

final class Operation: Foundation.Operation {
    private var _isExecuting = Atomic(false)
    private var _isFinished = Atomic(false)
    private var isFinishCalled = Atomic(false)

    override var isExecuting: Bool {
        get {
            _isExecuting.value
        }
        set {
            guard _isExecuting.value != newValue else {
                fatalError("Invalid state, operation is already (not) executing")
            }
            willChangeValue(forKey: "isExecuting")
            _isExecuting.value = newValue
            didChangeValue(forKey: "isExecuting")
        }
    }
    override var isFinished: Bool {
        get {
            _isFinished.value
        }
        set {
            guard !_isFinished.value else {
                fatalError("Invalid state, operation is already finished")
            }
            willChangeValue(forKey: "isFinished")
            _isFinished.value = newValue
            didChangeValue(forKey: "isFinished")
        }
    }

    typealias Starter = (_ finish: @escaping () -> Void) -> Void
    private let starter: Starter

    #if TRACK_ALLOCATIONS
    deinit {
        Allocations.decrement("Operation")
    }
    #endif

    init(starter: @escaping Starter) {
        self.starter = starter

        #if TRACK_ALLOCATIONS
        Allocations.increment("Operation")
        #endif
    }

    override func start() {
        guard !isCancelled else {
            isFinished = true
            return
        }
        isExecuting = true
        starter { [weak self] in
            self?._finish()
        }
    }

    private func _finish() {
        // Make sure that we ignore if `finish` is called more than once.
        if isFinishCalled.swap(to: true, ifEqual: false) {
            isExecuting = false
            isFinished = true
        }
    }
}

extension OperationQueue {
    /// Adds simple `BlockOperation`.
    func add(_ closure: @escaping () -> Void) -> BlockOperation {
        let operation = BlockOperation(block: closure)
        addOperation(operation)
        return operation
    }

    /// Adds asynchronous operation (`Nuke.Operation`) with the given starter.
    func add(_ starter: @escaping Operation.Starter) -> Operation {
        let operation = Operation(starter: starter)
        addOperation(operation)
        return operation
    }
}
