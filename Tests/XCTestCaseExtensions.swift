// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Foundation

extension XCTestCase {
    func expect(_ block: @noescape (fulfill: (Void) -> Void) -> Void) {
        let expectation = makeExpectation()
        block(fulfill: { expectation.fulfill() })
    }

    func makeExpectation() -> XCTestExpectation {
        return self.expectation(description: "GenericExpectation")
    }
    
    func expectNotification(_ name: Notification.Name, object: AnyObject? = nil, handler: XCNotificationExpectationHandler? = nil) -> XCTestExpectation {
        return self.expectation(forNotification: name.rawValue, object: object, handler: handler)
    }

    func wait(_ timeout: TimeInterval = 2.0, handler: XCWaitCompletionHandler? = nil) {
        self.waitForExpectations(timeout: timeout, handler: handler)
    }
}

// FIXME: remove (legacy)

/// `Result` is the type that represent either success or a failure.
public enum Result<V, E: Error> {
    case success(V), failure(E)
}

public extension Result {
    public var value: V? {
        if case let .success(val) = self { return val }
        return nil
    }
    
    public var error: E? {
        if case let .failure(err) = self { return err }
        return nil
    }
    
    public var isSuccess: Bool {
        return value != nil
    }
}

// MARK: - AnyError

/// Type erased error.
public struct AnyError: Error {
    public var cause: Error
    public init(_ cause: Error) {
        self.cause = (cause as? AnyError)?.cause ?? cause
    }
}
