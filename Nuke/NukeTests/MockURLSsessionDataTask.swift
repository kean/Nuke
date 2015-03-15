//
//  MockURLSsessionDataTask.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/14/15.
//  Copyright (c) 2015 Alexander Grebenyuk. All rights reserved.
//

import Foundation

let MockURLSsessionDataTaskDidResumeNotification = "didResume";
let MockURLSsessionDataTaskDidCancelNotification = "didCancel";

class MockURLSsessionDataTask: NSURLSessionDataTask {
    override func resume() {
        NSNotificationCenter.defaultCenter().postNotificationName(MockURLSsessionDataTaskDidResumeNotification, object: self)
    }
    override func cancel() {
        NSNotificationCenter.defaultCenter().postNotificationName(MockURLSsessionDataTaskDidCancelNotification, object: self)
    }
}
