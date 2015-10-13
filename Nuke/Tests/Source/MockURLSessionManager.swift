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
    var enabled = true {
        didSet {
            self.queue.suspended = !enabled
        }
    }
    var createdTaskCount = 0
    private let queue = NSOperationQueue()
    
    override func imageDataTaskWithRequest(request: ImageRequest, progressHandler: ImageDataLoadingProgressHandler, completionHandler: ImageDataLoadingCompletionHandler) -> NSURLSessionTask {
        self.queue.addOperationWithBlock {
            progressHandler(completedUnitCount: 50, totalUnitCount: 100)
            progressHandler(completedUnitCount: 100, totalUnitCount: 100)
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
