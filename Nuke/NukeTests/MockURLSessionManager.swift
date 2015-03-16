//
//  MockURLSessionManager.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/14/15.
//  Copyright (c) 2015 Alexander Grebenyuk. All rights reserved.
//

import Foundation
import Nuke

class MockURLSessionManager: URLSessionManager {
    var enabled = true
    var createdTaskCount = 0
    
    override func dataTaskWithRequest(request: NSURLRequest, completionHandler: (data: NSData?, response: NSURLResponse?, error: NSError?) -> Void) -> NSURLSessionDataTask {
        if self.enabled {
            let bundle = NSBundle(forClass: MockURLSessionManager.self)
            let URL = bundle.URLForResource("Image", withExtension: "jpg")
            let data = NSData(contentsOfURL: URL!)
            dispatch_async(dispatch_get_main_queue()) {
                completionHandler(data: data, response: nil, error: nil)
            }
        }
        self.createdTaskCount++
        return MockURLSsessionDataTask()
    }
}
