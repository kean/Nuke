// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

final class Operation: Foundation.Operation {
    override var isExecuting: Bool {
        get {
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            return _isExecuting
        }
        set {
            os_unfair_lock_lock(lock)
            _isExecuting = newValue
            os_unfair_lock_unlock(lock)

            willChangeValue(forKey: "isExecuting")
            didChangeValue(forKey: "isExecuting")
        }
    }

    override var isFinished: Bool {
        get {
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            return _isFinished
        }
        set {
            os_unfair_lock_lock(lock)
            _isFinished = newValue
            os_unfair_lock_unlock(lock)

            willChangeValue(forKey: "isFinished")
            didChangeValue(forKey: "isFinished")
        }
    }

    typealias Starter = @Sendable (_ finish: @Sendable @escaping () -> Void) -> Void
    private let starter: Starter

    private var _isExecuting = false
    private var _isFinished = false
    private var isFinishCalled = false
    private let lock: os_unfair_lock_t

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    init(starter: @escaping Starter) {
        self.starter = starter

        self.lock = .allocate(capacity: 1)
        self.lock.initialize(to: os_unfair_lock())
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
        os_unfair_lock_lock(lock)
        guard !isFinishCalled else {
            return os_unfair_lock_unlock(lock)
        }
        isFinishCalled = true
        os_unfair_lock_unlock(lock)

        isExecuting = false
        isFinished = true
    }
}

extension OperationQueue {
    /// Adds simple `BlockOperation`.
    func add(_ closure: @Sendable @escaping () -> Void) -> BlockOperation {
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
