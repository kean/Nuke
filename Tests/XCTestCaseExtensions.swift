// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
import Foundation

extension XCTestCase {
    @discardableResult
    func expectNotification(_ name: Notification.Name, object: AnyObject? = nil, handler: XCTNSNotificationExpectation.Handler? = nil) -> XCTestExpectation {
        return self.expectation(forNotification: name, object: object, handler: handler)
    }

    func wait(_ timeout: TimeInterval = 10.0, handler: XCWaitCompletionHandler? = nil) {
        self.waitForExpectations(timeout: timeout, handler: handler)
    }
}

// MARK: - XCTestCase (KVO)

extension XCTestCase {
    /// A replacement for keyValueObservingExpectation which used Swift key paths.
    /// - warning: Keep in mind that `changeHandler` will continue to get called
    /// even after expectation is fulfilled. The method itself can't reliably stop
    /// observing KVO in case its multithreaded.
    /// FIXME: Make symmetrical to XCTest variant?
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

struct XCTestExpectationFactory<T> {
    let testCase: XCTestCase
    let base: T
}

extension XCTestCase {
    func expect<T>(_ base: T) -> XCTestExpectationFactory<T> {
        return XCTestExpectationFactory(testCase: self, base: base)
    }
}

// MARK: - XCTestExpectationFactory (OperationQueue)

extension XCTestExpectationFactory where T: OperationQueue  {
    // This is still in more of experimental phaze, OperationQueue KVO
    // is probably not the most reliable way to do that.

    func toFinishWithPerformedOperationCount(_ expectedCount: Int) {
        let base = self.base
        precondition(base.isSuspended, "Queue must be suspended in order to reliably track when all expected operations are enqueued.")

        var isFinishing = false
        var isFinished = false
        let syncQueue = DispatchQueue(label: "XCTestCase.expectPerformedOperationCount")
        var distinctOperations = Set<Foundation.Operation>()

        testCase.expectation(for: base, keyPath: \.operations) { (_, change, expectation) in
            syncQueue.async { // Synchronize access to set.
                // See if there are any new operations added.
                let operations = base.operations
                distinctOperations.formUnion(operations)
                if distinctOperations.count == expectedCount && base.isSuspended {
                    syncQueue.after(ticks: 10) { // Wait a few ticks to make sure no more operations are enqueued.
                        base.isSuspended = false
                    }
                }

                // Wait a bit to make sure that there are no operations added after
                // the queue is empty. Also make sure that we don't fulfill twice.
                if operations.isEmpty && !isFinished {
                    if !isFinishing {
                        isFinishing = true
                        syncQueue.after(ticks: 10) {
                            isFinishing = false
                            if base.operations.isEmpty {
                                XCTAssertEqual(distinctOperations.count, expectedCount)
                                expectation.fulfill()
                                isFinished = true
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - ValuesExpectation

extension XCTestCase {
    class ValuesExpectation<Value: Equatable> {
        fileprivate let expectation: XCTestExpectation
        fileprivate let expected: [Value]
        private var _expected: [Value]
        private var _recorded = [Value]()

        init(expected: [Value], expectation: XCTestExpectation) {
            self.expected = expected
            self._expected = expected.reversed() // to be ably to popLast
            self.expectation = expectation
        }

        func received(_ newValue: Value) {
            _recorded.append(newValue)
            guard let value = _expected.popLast() else {
                XCTFail("Received unexpected value. Recorded: \(_recorded), Expected: \(expected)")
                return
            }
            XCTAssertEqual(newValue, value, "Recorded: \(_recorded), Expected: \(expected)")
            if _expected.isEmpty {
                expectation.fulfill()
            }
        }
    }

    func expect<Value: Equatable>(values: [Value]) -> ValuesExpectation<Value> {
        return ValuesExpectation(expected: values, expectation: self.expectation(description: "Expecting values: \(values)"))
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
