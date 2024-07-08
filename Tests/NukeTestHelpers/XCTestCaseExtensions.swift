// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
import Foundation
import Combine

extension XCTestCase {
    @discardableResult
    public func expectNotification(_ name: Notification.Name, object: AnyObject? = nil, handler: XCTNSNotificationExpectation.Handler? = nil) -> XCTestExpectation {
        return self.expectation(forNotification: name, object: object, handler: handler)
    }

    public func wait(_ timeout: TimeInterval = 5, handler: XCWaitCompletionHandler? = nil) {
        self.waitForExpectations(timeout: timeout, handler: handler)
    }
}

// MARK: - Publishers

extension XCTestCase {
    func expect<P: Publisher>(_ publisher: P) -> TestExpectationPublisher<P> {
        TestExpectationPublisher(test: self, publisher: publisher)
    }

    func record<P: Publisher>(_ publisher: P) -> TestRecordedPublisher<P> {
        let record = TestRecordedPublisher<P>()
        publisher.sink(receiveCompletion: {
            record.completion = $0
        }, receiveValue: {
            record.values.append($0)
        }).store(in: &cancellables)
        return record
    }

#if swift(>=5.10)
    // Safe because it's never mutated.
    nonisolated(unsafe) private static let cancellablesAK = malloc(1)!
#else
    private static let cancellablesAK = malloc(1)!
#endif

    fileprivate var cancellables: [AnyCancellable] {
        get { (objc_getAssociatedObject(self, XCTestCase.cancellablesAK) as? [AnyCancellable]) ?? [] }
        set { objc_setAssociatedObject(self, XCTestCase.cancellablesAK, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}

struct TestExpectationPublisher<P: Publisher> {
    let test: XCTestCase
    let publisher: P

    @discardableResult
    func toPublishSingleValue() -> TestRecordedPublisher<P> {
        let record = TestRecordedPublisher<P>()
        let expectation = test.expectation(description: "ValueEmitted")
        publisher.sink(receiveCompletion: { _ in
            // Do nothing
        }, receiveValue: {
            guard record.values.isEmpty else {
                return XCTFail("Already emitted value")
            }
            record.values.append($0)
            expectation.fulfill()
        }).store(in: &test.cancellables)
        return record
    }
}

final class TestRecordedPublisher<P: Publisher> {
    fileprivate(set) var values = [P.Output]()
    fileprivate(set) var completion: Subscribers.Completion<P.Failure>?

    var last: P.Output? {
        values.last
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
            DispatchQueue.main.async { // Synchronize access to `valuesExpectation`
                valuesExpectation.received(change.newValue!)
            }
        }
        observations.append(observation)
    }

#if swift(>=5.10)
    // Safe because it's never mutated.
    nonisolated(unsafe) private static let observationsAK = malloc(1)!
#else
    private static let observationsAK = malloc(1)!
#endif

    private var observations: [NSKeyValueObservation] {
        get {
            return (objc_getAssociatedObject(self, XCTestCase.observationsAK) as? [NSKeyValueObservation]) ?? []
        }
        set {
            objc_setAssociatedObject(self, XCTestCase.observationsAK, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

// MARK: - XCTestExpectationFactory

public struct TestExpectationOperationQueue {
    let test: XCTestCase
    let queue: OperationQueue

    @discardableResult
    public func toEnqueueOperationsWithCount(_ count: Int) -> OperationQueueObserver {
        let expectation = test.expectation(description: "Expect queue to enqueue \(count) operations")
        let observer = OperationQueueObserver(queue: queue)
        observer.didAddOperation = { _ in
            if observer.operations.count == count {
                observer.didAddOperation = nil
                expectation.fulfill()
            }
        }
        return observer
    }

    /// Fulfills an expectation as soon as a queue finished executing `n`
    /// operations (doesn't matter whether they were cancelled or executed).
    ///
    /// Automatically resumes a queue as soon as `n` operations are enqueued.
    @discardableResult
    public func toFinishWithEnqueuedOperationCount(_ count: Int) -> OperationQueueObserver {
        precondition(queue.isSuspended, "Queue must be suspended in order to reliably track when all expected operations are enqueued.")

        let expectation = test.expectation(description: "Expect queue to finish with \(count) operations")
        let observer = OperationQueueObserver(queue: queue)

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
    public func expect(_ queue: OperationQueue) -> TestExpectationOperationQueue {
        return TestExpectationOperationQueue(test: self, queue: queue)
    }
}

public struct TestExpectationOperation {
    let test: XCTestCase
    let operation: Operation

    // This is useful because KVO on Foundation.Operation is super flaky in Swift
    public func toCancel(with expectation: XCTestExpectation? = nil) {
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

    public func toUpdatePriority(from: Operation.QueuePriority = .normal, to: Operation.QueuePriority = .high) {
        XCTAssertEqual(operation.queuePriority, from)
        test.keyValueObservingExpectation(for: operation, keyPath: "queuePriority") { [weak operation] (_, _)  in
            XCTAssertEqual(operation?.queuePriority, to)
            return true
        }
    }
}

extension XCTestCase {
    public func expect(_ operation: Operation) -> TestExpectationOperation {
        return TestExpectationOperation(test: self, operation: operation)
    }
}

// MARK: - ValuesExpectation

extension XCTestCase {
    public class ValuesExpectation<Value> {
        private let expectation: XCTestExpectation
        private let expected: [Value]
        private let isEqual: (Value, Value) -> Bool
        private var _expected: [Value]
        private var _recorded = [Value]()

        init(expected: [Value], isEqual: @escaping (Value, Value) -> Bool, expectation: XCTestExpectation) {
            self.expected = expected
            self.isEqual = isEqual
            self._expected = expected.reversed() // to be ably to popLast
            self.expectation = expectation
        }

        public func received(_ newValue: Value) {
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

    public func expectProgress(_ values: [(Int64, Int64)]) -> ValuesExpectation<(Int64, Int64)> {
        return expect(values: values, isEqual: ==)
    }
}

// MARK: - OperationQueueObserver

public final class OperationQueueObserver {
    private let queue: OperationQueue
    // All recorded operations.
    public private(set) var operations = [Foundation.Operation]()
    private var _ops = Set<Foundation.Operation>()
    private var _observers = [NSKeyValueObservation]()
    private let _lock = NSLock()

    public var didAddOperation: ((Foundation.Operation) -> Void)?
    public var didFinishAllOperations: (() -> Void)?

    public init(queue: OperationQueue) {
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

// MARK: - Misc

func rnd() -> Int {
    return Int.random(in: 0 ..< .max)
}

func rnd(_ uniform: Int) -> Int {
    return Int.random(in: 0 ..< uniform)
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
