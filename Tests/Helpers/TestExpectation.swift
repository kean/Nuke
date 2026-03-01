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
/// The action closure is called after the KVO observation is set up.
func waitForOperations(on queue: OperationQueue, count: Int, while action: () -> Void) async -> [Foundation.Operation] {
    let expectation = TestExpectation()
    var seen = Set<Foundation.Operation>()
    var recorded = [Foundation.Operation]()
    let observer = queue.observe(\.operations) { queue, _ in
        for operation in queue.operations {
            if !seen.contains(operation) {
                seen.insert(operation)
                recorded.append(operation)
                if recorded.count >= count {
                    expectation.fulfill()
                }
            }
        }
    }
    action()
    await expectation.wait()
    withExtendedLifetime(observer) {}
    return recorded
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

/// Passively records operations added to a queue via KVO.
/// Use only when you need to observe operations during execution without waiting.
final class OperationQueueObserver {
    private(set) var operations = [Foundation.Operation]()
    private var seen = Set<Foundation.Operation>()
    private var observer: NSKeyValueObservation?

    init(queue: OperationQueue) {
        observer = queue.observe(\.operations) { [weak self] queue, _ in
            guard let self else { return }
            for operation in queue.operations {
                if !seen.contains(operation) {
                    seen.insert(operation)
                    operations.append(operation)
                }
            }
        }
    }
}
