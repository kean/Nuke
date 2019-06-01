// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import XCTest
import Foundation

extension XCTestCase {
    @discardableResult
    func expectNotification(_ name: Notification.Name, object: AnyObject? = nil, handler: XCTNSNotificationExpectation.Handler? = nil) -> XCTestExpectation {
        return self.expectation(forNotification: name, object: object, handler: handler)
    }

    func wait(_ timeout: TimeInterval = 10, handler: XCWaitCompletionHandler? = nil) {
        self.waitForExpectations(timeout: timeout, handler: handler)
    }
}

// MARK: - XCTestCase (KVO)

extension XCTestCase {
    /// A replacement for keyValueObservingExpectation which used Swift key paths.
    /// - warning: Keep in mind that `changeHandler` will continue to get called
    /// even after expectation is fulfilled. The method itself can't reliably stop
    /// observing KVO in case its multithreaded.
    func expectation<Object: NSObject, Value>(description: String = "", for object: Object, keyPath: KeyPath<Object, Value>, options: NSKeyValueObservingOptions = .new, _ changeHandler: @escaping (Object, NSKeyValueObservedChange<Value>, XCTestExpectation) -> Void) {
        let expectation = self.expectation(description: description)
        let observation = object.observe(keyPath, options: options) { (object, change) in
            changeHandler(object, change, expectation)
        }
        observations.append(observation)
    }

    func expect<Object: NSObject, Value: Equatable>(values: [Value], for object: Object, keyPath: KeyPath<Object, Value>, changeHandler: ((Object, NSKeyValueObservedChange<Value>) -> Void)? = nil) {
        let valuesExpectation = self.expect(values: values)
        let observation = object.observe(keyPath, options: [.new]) { (object, change) in
            changeHandler?(object, change)
            DispatchQueue.main.async { // Syncrhonize access to `valuesExpectation`
                valuesExpectation.received(change.newValue!)
            }
        }
        observations.append(observation)
    }

    private static var observationsAK = "ImageViewController.AssociatedKey"

    private var observations: [NSKeyValueObservation] {
        get {
            return (objc_getAssociatedObject(self, &XCTestCase.observationsAK) as? [NSKeyValueObservation]) ?? []
        }
        set {
            objc_setAssociatedObject(self, &XCTestCase.observationsAK, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

// MARK: - XCTestExpectationFactory

struct TestExpectationOperationQueue {
    let test: XCTestCase
    let queue: OperationQueue

    @discardableResult
    func toEnqueueOperationsWithCount(_ count: Int) -> OperationQueueObserver {
        let observer = OperationQueueObserver(queue: queue)
        let expectation = test.expectation(description: "Expect queue to enqueue \(count) operations")
        observer.didAddOperation = { _ in
            if observer.operations.count == count {
                observer.didAddOperation = nil
                expectation.fulfill()
            }
        }
        return observer
    }

    /// Fulfills an expectation as soon as a queue finished exeucting `n`
    /// operations (doesn't matter whether they were cancelled or executed).
    ///
    /// Automatically resumes a queue as soon as `n` operations are enqueued.
    @discardableResult
    func toFinishWithEnqueuedOperationCount(_ count: Int) -> OperationQueueObserver {
        precondition(queue.isSuspended, "Queue must be suspended in order to reliably track when all expected operations are enqueued.")

        let observer = OperationQueueObserver(queue: queue)
        let expectation = test.expectation(description: "Expect queue to finish with \(count) operations")

        observer.didAddOperation = { _ in
            // We don't expect any more operations added after that
            XCTAssertTrue(self.queue.isSuspended, "More operations were added to the queue then were expected")
            if observer.operations.count == count {
                self.queue.isSuspended = false
            }
        }
        observer.didFinishAllOperations = {
            expectation.fulfill()

            // Release observer
            observer.didAddOperation = nil
            observer.didFinishAllOperations = nil
        }
        return observer
    }
}

extension XCTestCase {
    func expect(_ queue: OperationQueue) -> TestExpectationOperationQueue {
        return TestExpectationOperationQueue(test: self, queue: queue)
    }
}

struct TestExpectationOperation {
    let test: XCTestCase
    let operation: Operation

    // This is useful because KVO on Foundation.Operation is super flaky in Swift
    func toCancel(with expectation: XCTestExpectation? = nil) {
        let expectation = expectation ?? self.test.expectation(description: "Cancelled")
        let operation = self.operation

        func check() {
            if operation.isCancelled {
                expectation.fulfill()
            } else {
                // Use GCD because Timer with closures not available on iOS 9
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(5)) {
                    check()
                }
            }
        }
        check()
    }

    func toUpdatePriority(from: Operation.QueuePriority = .normal, to: Operation.QueuePriority = .high) {
        XCTAssertEqual(operation.queuePriority, from)
        test.keyValueObservingExpectation(for: operation, keyPath: "queuePriority") { (_, _) in
            XCTAssertEqual(self.operation.queuePriority, to)
            return true
        }
    }
}

extension XCTestCase {
    func expect(_ operation: Operation) -> TestExpectationOperation {
        return TestExpectationOperation(test: self, operation: operation)
    }
}

// MARK: - ValuesExpectation

extension XCTestCase {
    class ValuesExpectation<Value> {
        fileprivate let expectation: XCTestExpectation
        fileprivate let expected: [Value]
        private let isEqual: (Value, Value) -> Bool
        private var _expected: [Value]
        private var _recorded = [Value]()

        init(expected: [Value], isEqual: @escaping (Value, Value) -> Bool, expectation: XCTestExpectation) {
            self.expected = expected
            self.isEqual = isEqual
            self._expected = expected.reversed() // to be ably to popLast
            self.expectation = expectation
        }

        func received(_ newValue: Value) {
            _recorded.append(newValue)
            guard let value = _expected.popLast() else {
                XCTFail("Received unexpected value. Recorded: \(_recorded), Expected: \(expected)")
                return
            }
            XCTAssertTrue(isEqual(newValue, value), "Recorded: \(_recorded), Expected: \(expected)")
            if _expected.isEmpty {
                expectation.fulfill()
            }
        }
    }

    func expect<Value: Equatable>(values: [Value]) -> ValuesExpectation<Value> {
        return ValuesExpectation(expected: values, isEqual: ==, expectation: self.expectation(description: "Expecting values: \(values)"))
    }

    func expect<Value>(values: [Value], isEqual: @escaping (Value, Value) -> Bool) -> ValuesExpectation<Value> {
        return ValuesExpectation(expected: values, isEqual: isEqual, expectation: self.expectation(description: "Expecting values: \(values)"))
    }

    func expectProgress(_ values: [(Int64, Int64)]) -> ValuesExpectation<(Int64, Int64)> {
        return expect(values: values, isEqual: ==)
    }
}

// MARK: - OperationQueueObserver

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
        let observer = queue.observe(\.operations) { [weak self] (_, change) in
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

// MARK: - Misc

func rnd() -> Int {
    return Int(arc4random())
}

func rnd(_ uniform: Int) -> Int {
    return Int(arc4random_uniform(UInt32(uniform)))
}

extension DispatchQueue {
    func after(ticks: Int, _ closure: @escaping () -> Void) {
        if ticks == 0 {
            closure()
        } else {
            async {
                self.after(ticks: ticks - 1, closure)
            }
        }
    }
}

extension Array {
    func randomItem() -> Element {
        let index = Int(arc4random_uniform(UInt32(self.count)))
        return self[index]
    }
}
