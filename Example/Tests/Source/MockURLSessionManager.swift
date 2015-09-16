//
//  MockImageDataLoader.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/14/15.
//  Copyright (c) 2015 Alexander Grebenyuk. All rights reserved.
//

import Foundation
import Nuke

class MockImageDataLoader: ImageDataLoader {
    var enabled = true
    var createdTaskCount = 0
    
    override func imageDataTaskWithURL(url: NSURL, progressHandler: ImageDataLoadingProgressHandler?, completionHandler: ImageDataLoadingCompletionHandler) -> NSURLSessionDataTask {
        if self.enabled {
            let bundle = NSBundle(forClass: MockImageDataLoader.self)
            let URL = bundle.URLForResource("Image", withExtension: "jpg")
            let data = NSData(contentsOfURL: URL!)
            dispatch_async(dispatch_get_main_queue()) {
                completionHandler(data: data, response: nil, error: nil)
            }
        }
        self.createdTaskCount++
        return MockURLSessionDataTask()
    }
}
