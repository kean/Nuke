//
//  XCTestCase+Nuke.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 01/10/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import XCTest
import Foundation

extension XCTestCase {
    public func expect(block: (fulfill: (Void) -> Void) -> Void) {
        let expectation = self.expectation()
        block(fulfill: { expectation.fulfill() })
    }

    public func expectation() -> XCTestExpectation {
        return self.expectationWithDescription("GenericExpectation")
    }

    public func expectNotification(name: String, object: AnyObject? = nil, handler: XCNotificationExpectationHandler? = nil) -> XCTestExpectation {
        return self.expectationForNotification(name, object: object, handler: handler)
    }

    public func wait(timeout: NSTimeInterval = 2.0, handler: XCWaitCompletionHandler? = nil) {
        self.waitForExpectationsWithTimeout(timeout, handler: handler)
    }
}