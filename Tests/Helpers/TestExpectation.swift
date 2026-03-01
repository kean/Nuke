// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

final class TestExpectation: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State = .idle

    private enum State {
        case idle
        case fulfilled
        case awaiting(CheckedContinuation<Void, Never>)
    }

    init() {}

    func fulfill() {
        lock.lock()
        switch state {
        case .idle:
            state = .fulfilled
            lock.unlock()
        case .awaiting(let continuation):
            state = .fulfilled
            lock.unlock()
            continuation.resume()
        case .fulfilled:
            lock.unlock()
        }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            switch state {
            case .idle:
                state = .awaiting(continuation)
                lock.unlock()
            case .fulfilled:
                lock.unlock()
                continuation.resume()
            case .awaiting:
                lock.unlock()
                preconditionFailure("wait() called multiple times")
            }
        }
    }
}

extension TestExpectation {
    convenience init(notification name: Notification.Name, object: AnyObject? = nil) {
        self.init()
        let ref = TokenRef()
        ref.token = NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
            if let token = ref.token { NotificationCenter.default.removeObserver(token) }
            self?.fulfill()
        }
    }
}

private final class TokenRef: @unchecked Sendable {
    var token: NSObjectProtocol?
}

func notification(_ name: Notification.Name, object: AnyObject? = nil, while action: () -> Void = {}) async {
    let expectation = TestExpectation(notification: name, object: object)
    action()
    await expectation.wait()
}

// MARK: - Operation Queue Helpers

/// Waits for the specified number of operations to be enqueued on the queue.
func waitForOperations(on observer: OperationQueueObserver, count: Int) async {
    if observer.operations.count >= count { return }
    let expectation = TestExpectation()
    observer.didAddOperation = { _ in
        if observer.operations.count >= count {
            observer.didAddOperation = nil
            expectation.fulfill()
        }
    }
    await expectation.wait()
}

/// Waits for a priority change on an operation using KVO.
/// The action closure is called after the KVO observation is set up.
func waitForPriorityChange(of operation: Foundation.Operation, to: Foundation.Operation.QueuePriority = .high, while action: () -> Void) async {
    let expectation = TestExpectation()
    let observer = operation.observe(\.queuePriority, options: [.new, .initial]) { operation, _ in
        if operation.queuePriority == to {
            expectation.fulfill()
        }
    }
    action()
    await expectation.wait()
    withExtendedLifetime(observer) {}
}

/// Waits for an operation to be cancelled using KVO.
/// The action closure is called after the KVO observation is set up.
func waitForCancellation(of operation: Foundation.Operation, while action: () -> Void) async {
    let expectation = TestExpectation()
    let observer = operation.observe(\.isCancelled, options: [.new, .initial]) { operation, _ in
        if operation.isCancelled {
            expectation.fulfill()
        }
    }
    action()
    await expectation.wait()
    withExtendedLifetime(observer) {}
}

/// Waits for a queue to finish all expected operations.
/// The queue must be suspended before calling this function.
func waitForQueueCompletion(queue: OperationQueue, observer: OperationQueueObserver, expectedCount: Int) async {
    precondition(queue.isSuspended, "Queue must be suspended")
    let expectation = TestExpectation()
    observer.didAddOperation = { _ in
        if observer.operations.count == expectedCount {
            queue.isSuspended = false
        }
    }
    observer.didFinishAllOperations = {
        expectation.fulfill()
        observer.didAddOperation = nil
        observer.didFinishAllOperations = nil
    }
    await expectation.wait()
}

final class OperationQueueObserver {
    private let queue: OperationQueue
    // All recorded operations.
    private(set) var operations = [Foundation.Operation]()
    private var _ops = Set<Foundation.Operation>()
    private var _observers = [NSKeyValueObservation]()
    private let _lock = NSLock()

    var didAddOperation: ((Foundation.Operation) -> Void)?
    var didFinishAllOperations: (() -> Void)?

    init(queue: OperationQueue) {
        self.queue = queue

        _startObservingOperations()
    }

    private func _startObservingOperations() {
        let observer = queue.observe(\.operations) { [weak self] _, _ in
            self?._didUpdateOperations()
        }
        _observers.append(observer)
    }

    private func _didUpdateOperations() {
        _lock.lock()
        for operation in queue.operations {
            if !_ops.contains(operation) {
                _ops.insert(operation)
                operations.append(operation)
                didAddOperation?(operation)
            }
        }
        if queue.operations.isEmpty {
            didFinishAllOperations?()
        }
        _lock.unlock()
    }
}
