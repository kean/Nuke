// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke

final class TestExpectation: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State = .idle
    fileprivate var recorder: TaskQueueObserver?

    private enum State {
        case idle
        case fulfilled
        case cancelled
        case awaiting(CheckedContinuation<Bool, Never>)
    }

    init() {}

    func fulfill() {
        let continuation = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            switch state {
            case .idle:
                state = .fulfilled
                return nil
            case .awaiting(let continuation):
                state = .fulfilled
                return continuation
            case .fulfilled, .cancelled:
                return nil
            }
        }
        continuation?.resume(returning: true)
    }

    func wait(timeout: Duration = .seconds(60)) async {
        let fulfilled = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await self.waitInternal()
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let result = await group.next()
            group.cancelAll()
            return result ?? false
        }
        if !fulfilled, !Task.isCancelled {
            Issue.record("TestExpectation timed out after \(timeout)")
        }
    }

    // Returns true if genuinely fulfilled, false if cancelled.
    private func waitInternal() async -> Bool {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let result = lock.withLock { () -> Bool? in
                    switch state {
                    case .idle:
                        state = .awaiting(continuation)
                        return nil
                    case .fulfilled:
                        return true
                    case .cancelled:
                        return false
                    case .awaiting:
                        preconditionFailure("wait() called multiple times")
                    }
                }
                if let result {
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            let continuation = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
                switch state {
                case .idle:
                    state = .cancelled  // inner block hasn't run yet; it will see .cancelled and resume
                    return nil
                case .awaiting(let c):
                    state = .cancelled
                    return c
                case .fulfilled, .cancelled:
                    return nil
                }
            }
            continuation?.resume(returning: false)
        }
    }
}

extension TestExpectation {
    convenience init(notification name: Notification.Name, object: AnyObject? = nil) {
        self.init()
        let observer = NotificationObserver()
        let token = NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
            observer.remove()
            self?.fulfill()
        }
        observer.store(token)
    }

    /// Creates a test expectation that waits for a given number of operations
    /// to be enqueued on the given `TaskQueue`.
    @ImagePipelineActor convenience init(queue: TaskQueue, count: Int) {
        self.init()
        recorder = TaskQueueObserver(queue: queue) { [weak self] enqueuedCount in
            if enqueuedCount >= count {
                self?.fulfill()
            }
        }
    }

    /// The operations enqueued since the expectation was created with
    /// ``init(queue:count:)``.
    var operations: [TaskQueue.Operation] {
        recorder?.operations ?? []
    }
}

/// Owns the token returned by `NotificationCenter.addObserver`. The notification
/// can be delivered on another thread before `addObserver` returns, so the token
/// handoff has to be synchronized, and the observer has to be removed exactly
/// once no matter which side wins the race.
private final class NotificationObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var token: NSObjectProtocol?
    private var isRemoved = false

    func store(_ token: NSObjectProtocol) {
        let isRemoved = lock.withLock { () -> Bool in
            if !self.isRemoved { self.token = token }
            return self.isRemoved
        }
        if isRemoved { NotificationCenter.default.removeObserver(token) }
    }

    func remove() {
        let token = lock.withLock { () -> NSObjectProtocol? in
            isRemoved = true
            defer { self.token = nil }
            return self.token
        }
        if let token { NotificationCenter.default.removeObserver(token) }
    }
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
        let previous = onEvent
        let expectation = TestExpectation(queue: self, count: count)
        action()
        await expectation.wait()
        onEvent = previous
        return expectation.operations
    }
}

/// Waits until the priority of the operation changes to the given one. The
/// operation reports the change whether or not it is in a queue.
@ImagePipelineActor
func waitForPriorityChange(of operation: TaskQueue.Operation, to target: TaskPriority = .high, while action: () -> Void) async {
    if operation.priority == target { action(); return }
    let expectation = TestExpectation()
    let previous = operation.onPriorityChanged
    operation.onPriorityChanged = { priority in
        previous?(priority)
        if priority == target { expectation.fulfill() }
    }
    action()
    await expectation.wait()
    operation.onPriorityChanged = previous
}

/// Waits until the operation is cancelled, whether or not it is in a queue.
@ImagePipelineActor
func waitForCancellation(of operation: TaskQueue.Operation, while action: () -> Void) async {
    if operation.isCancelled { action(); return }
    let expectation = TestExpectation()
    let previous = operation.onCancelled
    operation.onCancelled = {
        previous?()
        expectation.fulfill()
    }
    action()
    await expectation.wait()
    operation.onCancelled = previous
}

/// Polls `condition` until it holds or the timeout elapses, giving the run loop
/// a chance to make progress in between. Use it for state that is updated by
/// something that doesn't offer a callback, such as a UIKit animation.
func waitUntil(timeout: Duration = .seconds(10), isolation: isolated (any Actor)? = #isolation, _ condition: () -> Bool) async {
    let clock = ContinuousClock()
    let start = clock.now
    while clock.now - start < timeout {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    if !condition() {
        Issue.record("waitUntil timed out after \(timeout)")
    }
}

/// Waits for the work already scheduled on the pipeline actor, such as the
/// delegate callbacks of the tasks that just finished.
func drainPipeline() async {
    await Task { @ImagePipelineActor in }.value
}

/// Waits for the work already scheduled on the pipeline actor, such as the
/// calls made to a prefetcher, then for the main queue to run what that work
/// dispatched to it, such as the prefetcher's `didComplete`.
func waitForDelivery() async {
    await drainPipeline()
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.async { continuation.resume() }
    }
}

/// Gives any pending continuations on the caller's actor a chance to run.
func drainPendingWork(isolation: isolated (any Actor)? = #isolation) async {
    for _ in 0..<10 { await Task.yield() }
}

/// A one-shot gate: `wait()` suspends until someone calls `open()`. Use it to
/// hold code at a known suspension point while the test does something else.
final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [UnsafeContinuation<Void, Never>] = []

    init() {}

    func open() {
        let waiters = lock.withLock { () -> [UnsafeContinuation<Void, Never>] in
            isOpen = true
            defer { self.waiters = [] }
            return self.waiters
        }
        for waiter in waiters { waiter.resume() }
    }

    func wait() async {
        await withUnsafeContinuation { continuation in
            let isOpen = lock.withLock { () -> Bool in
                if !self.isOpen { waiters.append(continuation) }
                return self.isOpen
            }
            if isOpen { continuation.resume() }
        }
    }
}

/// A simple mutable reference wrapper for use in test closures.
final class Ref<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Holds a weak reference to an object. Use it to test object lifetimes.
final class WeakRef<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T? = nil) { self.value = value }
}

/// An array that callbacks on any thread can append to.
final class LockedArray<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [Element] = []

    init() {}

    func append(_ element: Element) {
        lock.withLock { elements.append(element) }
    }

    var values: [Element] {
        lock.withLock { elements }
    }

    var count: Int {
        values.count
    }
}

extension TaskQueue {
    /// Waits until all enqueued operations have finished executing, or were
    /// cancelled before they started. Modeled after
    /// `OperationQueue.waitUntilAllOperationsAreFinished()`.
    func waitUntilAllOperationsAreFinished() async {
        guard operationCount > 0 else { return }
        let expectation = TestExpectation()
        let previous = onEvent
        onEvent = { [weak self] event in
            previous?(event)
            // An operation leaves the queue when it finishes, or when it is
            // cancelled while it waits.
            if let self, self.operationCount == 0 {
                expectation.fulfill()
            }
        }
        await expectation.wait()
        onEvent = previous
    }
}

/// Records the operations enqueued on a `TaskQueue`, in order.
///
/// It chains the queue's `onEvent` handler instead of replacing it, so the
/// observers and expectations installed before it keep working.
final class TaskQueueObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var _operations = [TaskQueue.Operation]()

    var operations: [TaskQueue.Operation] {
        lock.withLock { _operations }
    }

    /// - parameter onEnqueued: Called with the number of operations enqueued
    ///   so far, each time one is.
    @ImagePipelineActor
    init(queue: TaskQueue, onEnqueued: @escaping (Int) -> Void = { _ in }) {
        let previous = queue.onEvent
        queue.onEvent = { [weak self] event in
            previous?(event)
            guard case .enqueued(let operation) = event, let self else { return }
            let count = self.lock.withLock {
                self._operations.append(operation)
                return self._operations.count
            }
            onEnqueued(count)
        }
    }
}
