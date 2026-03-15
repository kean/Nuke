// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke

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

    func wait(timeout: Duration = .seconds(60)) async {
        let fulfilled = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await self.waitInternal()
                return true
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let result = await group.next()!
            group.cancelAll()
            return result
        }
        if !fulfilled, !Task.isCancelled {
            Issue.record("TestExpectation timed out after \(timeout)")
        }
    }

    private func waitInternal() async {
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

    /// Creates a test expectation that waits for a given number of operations
    /// to be enqueued on the given `TaskQueue`.
    @ImagePipelineActor convenience init(queue: TaskQueue, count: Int) {
        self.init()
        let recorder = TaskQueueOperationRecorder()
        self.recorder = recorder
        queue.onEvent = { [weak self] event in
            if case .enqueued(let op) = event {
                recorder.record(op)
                if recorder.operations.count >= count {
                    self?.fulfill()
                }
            }
        }
    }

    var operations: [TaskQueue.Operation] {
        (recorder as? TaskQueueOperationRecorder)?.operations ?? []
    }
}

private final class TaskQueueOperationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _operations = [TaskQueue.Operation]()

    var operations: [TaskQueue.Operation] {
        lock.withLock { _operations }
    }

    func record(_ operation: TaskQueue.Operation) {
        lock.withLock {
            _operations.append(operation)
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

// MARK: - TaskQueue Helpers

extension TaskQueue {
    var operationCount: Int { pendingCount + runningCount }

    /// Waits for the specified number of operations to be enqueued.
    func waitForOperations(count: Int, while action: () -> Void) async -> [TaskQueue.Operation] {
        let expectation = TestExpectation(queue: self, count: count)
        action()
        await expectation.wait()
        return expectation.operations
    }

    /// Waits for a priority change on a TaskQueue.Operation managed by this queue.
    func waitForPriorityChange(of operation: TaskQueue.Operation, to target: TaskPriority = .high, while action: () -> Void) async {
        if operation.priority == target { action(); return }
        let expectation = TestExpectation()
        let previous = onEvent
        onEvent = { event in
            previous?(event)
            if case .priorityChanged(let op) = event, op === operation, op.priority == target {
                expectation.fulfill()
            }
        }
        action()
        await expectation.wait()
        onEvent = previous
    }

    /// Waits for an operation managed by this queue to be cancelled.
    func waitForCancellation(of operation: TaskQueue.Operation, while action: () -> Void) async {
        if operation.isCancelled { action(); return }
        let expectation = TestExpectation()
        let previous = onEvent
        onEvent = { event in
            previous?(event)
            if case .cancelled(let op) = event, op === operation {
                expectation.fulfill()
            }
        }
        action()
        await expectation.wait()
        onEvent = previous
    }
}

/// Waits for a priority change on a standalone TaskQueue.Operation (not in a queue).
@ImagePipelineActor
func waitForPriorityChange(of operation: TaskQueue.Operation, to target: TaskPriority = .high, while action: () -> Void) async {
    if operation.priority == target { action(); return }
    action()
    while operation.priority != target { await Task.yield() }
}

/// Waits for a standalone TaskQueue.Operation to be cancelled (not in a queue).
@ImagePipelineActor
func waitForCancellation(of operation: TaskQueue.Operation, while action: () -> Void) async {
    if operation.isCancelled { action(); return }
    action()
    while !operation.isCancelled { await Task.yield() }
}

/// A simple mutable reference wrapper for use in test closures.
final class Ref<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

extension TaskQueue {
    /// Waits until all enqueued operations have finished executing.
    /// Modeled after `OperationQueue.waitUntilAllOperationsAreFinished()`.
    func waitUntilAllOperationsAreFinished() async {
        guard operationCount > 0 else { return }
        let expectation = TestExpectation()
        let previous = onEvent
        onEvent = { [weak self] event in
            previous?(event)
            if case .finished = event, let self, self.operationCount == 0 {
                expectation.fulfill()
            }
        }
        await expectation.wait()
        onEvent = previous
    }
}

/// Passively records operations enqueued on a TaskQueue.
/// Use only when you need to observe operations during execution without waiting.
@ImagePipelineActor
final class TaskQueueObserver: Sendable {
    private(set) var operations = [TaskQueue.Operation]()

    init(queue: TaskQueue) {
        queue.onEvent = { [weak self] event in
            if case .enqueued(let op) = event {
                self?.operations.append(op)
            }
        }
    }
}
