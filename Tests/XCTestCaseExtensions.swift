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
