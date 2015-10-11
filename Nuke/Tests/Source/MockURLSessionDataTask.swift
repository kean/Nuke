//
//  MockURLSessionDataTask.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/14/15.
//  Copyright (c) 2015 Alexander Grebenyuk. All rights reserved.
//

import Foundation

let MockURLSessionDataTaskDidResumeNotification = "didResume"
let MockURLSessionDataTaskDidCancelNotification = "didCancel"
let MockURLSessionDataTaskDidSuspendNotification = "didSuspend"

class MockURLSessionDataTask: NSURLSessionDataTask {
    override func resume() {
        NSNotificationCenter.defaultCenter().postNotificationName(MockURLSessionDataTaskDidResumeNotification, object: self)
    }
    override func suspend() {
        NSNotificationCenter.defaultCenter().postNotificationName(MockURLSessionDataTaskDidSuspendNotification, object: self)
    }
    override func cancel() {
        NSNotificationCenter.defaultCenter().postNotificationName(MockURLSessionDataTaskDidCancelNotification, object: self)
    }
}
