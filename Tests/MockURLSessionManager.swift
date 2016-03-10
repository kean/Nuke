//
//  MockImageDataLoader.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/14/15.
//  Copyright (c) 2016 Alexander Grebenyuk (github.com/kean). All rights reserved.
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

    override func taskWith(request: ImageRequest, progress: ImageDataLoadingProgress, completion: ImageDataLoadingCompletion) -> NSURLSessionTask {
        self.queue.addOperationWithBlock {
            progress(completed: 50, total: 100)
            progress(completed: 100, total: 100)
            let bundle = NSBundle(forClass: MockImageDataLoader.self)
            let URL = bundle.URLForResource("Image", withExtension: "jpg")
            let data = NSData(contentsOfURL: URL!)
            dispatch_async(dispatch_get_main_queue()) {
                completion(data: data, response: nil, error: nil)
            }
        }
        self.createdTaskCount += 1
        return MockURLSessionDataTask()
    }
}
