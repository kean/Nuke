// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

final class TestExpectation: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State = .idle
    fileprivate var recorder: AnyObject?

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

    convenience init(queue: OperationQueue, count: Int) {
        self.init()
        let recorder = OperationRecorder()
        self.recorder = recorder
        recorder.observer = queue.observe(\.operations) { [weak self] queue, _ in
            var shouldFulfill = false
            for operation in queue.operations {
                if recorder.record(operation) {
                    if recorder.operations.count >= count {
                        shouldFulfill = true
                    }
                }
            }
            if shouldFulfill {
                self?.fulfill()
            }
        }
    }

    var operations: [Foundation.Operation] {
        (recorder as? OperationRecorder)?.operations ?? []
    }
}

private final class OperationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = Set<Foundation.Operation>()
    private var _operations = [Foundation.Operation]()
    var observer: NSKeyValueObservation?

    var operations: [Foundation.Operation] {
        lock.withLock { _operations }
    }

    func record(_ operation: Foundation.Operation) -> Bool {
        lock.withLock {
            guard !seen.contains(operation) else { return false }
            seen.insert(operation)
            _operations.append(operation)
            return true
        }
    }
}

private final class TokenRef: @unchecked Sendable {
    var token: NSObjectProtocol?
}

func notification(_ name: Notification.Name, object: AnyObject? = nil, isolation: isolated (any Actor)? = #isolation, while action: () -> Void = {}) async {
    let expectation = TestExpectation(notification: name, object: object)
    action()
    await expectation.wait()
}

// MARK: - Operation Queue Helpers

/// Waits for the specified number of operations to be enqueued on the queue.
/// The action closure is called after the KVO observation is set up.
func waitForOperations(on queue: OperationQueue, count: Int, isolation: isolated (any Actor)? = #isolation, while action: () -> Void) async -> [Foundation.Operation] {
    let expectation = TestExpectation(queue: queue, count: count)
    action()
    await expectation.wait()
    return expectation.operations
}

/// Waits for a priority change on an operation using KVO.
/// The action closure is called after the KVO observation is set up.
func waitForPriorityChange(of operation: Foundation.Operation, to: Foundation.Operation.QueuePriority = .high, isolation: isolated (any Actor)? = #isolation, while action: () -> Void) async {
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
func waitForCancellation(of operation: Foundation.Operation, isolation: isolated (any Actor)? = #isolation, while action: () -> Void) async {
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

/// A simple mutable reference wrapper for use in test closures.
final class Ref<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Passively records operations added to a queue via KVO.
/// Use only when you need to observe operations during execution without waiting.
final class OperationQueueObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var _operations = [Foundation.Operation]()
    private var seen = Set<Foundation.Operation>()
    private var observer: NSKeyValueObservation?

    var operations: [Foundation.Operation] {
        lock.withLock { _operations }
    }

    init(queue: OperationQueue) {
        observer = queue.observe(\.operations) { [weak self] queue, _ in
            guard let self else { return }
            lock.withLock {
                for operation in queue.operations {
                    if !seen.contains(operation) {
                        seen.insert(operation)
                        _operations.append(operation)
                    }
                }
            }
        }
    }
}
