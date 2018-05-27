// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
import Foundation

extension XCTestCase {
    func test(_ name: String, _ closure: @escaping () -> Void) {
        closure()
    }

    func expect(_ block: (_ fulfill: @escaping () -> Void) -> Void) {
        let expectation = self.expectation(description: "Generic expectation")
        block({ expectation.fulfill() })
    }

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

// MARK: - XCTestCase (OperationQueue)

extension XCTestCase {
    // This is still in more of experimental phaze, relying on OperationQueue KVO
    // is probably not the most reliable way to do that.

    func expectPerformedOperationCount(_ expectedCount: Int, on queue: OperationQueue) {
        precondition(queue.isSuspended, "Queue must be suspended in order to reliably track when all expected operations are enqueued.")

        var set = Set<Foundation.Operation>()
        self.expectation(for: queue, keyPath: \.operations) { (_, change, expectation) in
            DispatchQueue.main.async { // Synchronize access to set.
                let operations = change.newValue ?? []
                set.formUnion(operations)
                if set.count == expectedCount {
                    after(ticks: 3) { // Wait a few ticks to make sure no more operations are enqueued.
                        queue.isSuspended = false
                    }
                }
                if operations.isEmpty {
                    XCTAssertEqual(set.count, expectedCount)
                    expectation.fulfill()
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

func after(ticks: Int, _ closure: @escaping () -> Void) {
    if ticks == 0 {
        closure()
    } else {
        DispatchQueue.main.async {
            after(ticks: ticks - 1, closure)
        }
    }
}

extension Array {
    func randomItem() -> Element {
        let index = Int(arc4random_uniform(UInt32(self.count)))
        return self[index]
    }
}
