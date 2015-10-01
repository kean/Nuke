//
//  MockURLSessionDataTask.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/14/15.
//  Copyright (c) 2015 Alexander Grebenyuk. All rights reserved.
//

import UIKit

let MockURLSessionDataTaskDidResumeNotification = "didResume"
let MockURLSessionDataTaskDidCancelNotification = "didCancel"

class MockURLSessionDataTask: NSURLSessionDataTask {
    override func resume() {
        NSNotificationCenter.defaultCenter().postNotificationName(MockURLSessionDataTaskDidResumeNotification, object: self)
    }
    override func cancel() {
        NSNotificationCenter.defaultCenter().postNotificationName(MockURLSessionDataTaskDidCancelNotification, object: self)
    }
}
