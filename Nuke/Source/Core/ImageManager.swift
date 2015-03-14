// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation

public enum ImageContentMode {
    case AspectFill
    case AspectFit
}

let ImageMaximumSize = CGSizeMake(CGFloat.max, CGFloat.max)

public typealias ImageCompletionHandler = (ImageResponse) -> Void

public class ImageManager {
    let queue = dispatch_queue_create("ImageManager-InternalSerialQueue", DISPATCH_QUEUE_SERIAL)
    var sessionTasks = [ImageSessionTaskKey: ImageSessionTask]()
    
    public init() {
        
    }
    
    public func imageTaskWithRequest(request: ImageRequest, completionHandler: ImageCompletionHandler?) -> ImageTask {
        // TODO: Create canonical request
        return ImageTaskInternal(manager: self, request: request, completionHandler: completionHandler)
    }
    
    public func startPreheatingImages(requests: [ImageRequest]) {
        
    }
    
    public func stopPreheatingImages(request: [ImageRequest]) {
        
    }
    
    public func stopPreheatingImages() {
        
    }
    
    func resumeTask(task: ImageTaskInternal) {
        // TODO: Cache lookup
        dispatch_async(self.queue) {
            // TODO: Check if task can be executed at the moment (see preheating)
            if (task.state == .Suspended) {
                // TODO: Make it possible to suspend image task!
                let sessionTaskKey = ImageSessionTaskKey(task.request)
                var sessionTask: ImageSessionTask! = self.sessionTasks[sessionTaskKey]
                if sessionTask == nil {
                    let request = NSURLRequest(URL: task.request.URL)
                    let dataTask = NSURLSession.sharedSession().dataTaskWithRequest(request, completionHandler: { (data: NSData!, response: NSURLResponse!, error: NSError!) -> Void in
                        // TODO: Handle completion
                    })
                    sessionTask = ImageSessionTask(dataTask: dataTask)
                    self.sessionTasks[sessionTaskKey] = sessionTask
                }
                
            }
        }
    }
    
    func cancelTask(task: ImageTaskInternal) {
        dispatch_async(self.queue) {
            // TODO: Find internal task
        }
    }
    
    enum ImageTaskState {
        case Suspended
        case Running
        case Completed
    }
    
    class ImageTaskInternal: ImageTask {
        var sessionTask: ImageSessionTask?
        var state = ImageTaskState.Suspended
        
        // TODO: Make weak?
        let manager: ImageManager
        
        init(manager: ImageManager, request: ImageRequest, completionHandler: ImageCompletionHandler?) {
            self.manager = manager
            super.init(request: request, completionHandler: completionHandler)
        }
        
        override func resume() {
            self.manager.resumeTask(self)
        }
        
        override func cancel() {
            self.manager.cancelTask(self)
        }
    }
    
    class ImageSessionTask {
        let dataTask: NSURLSessionDataTask
        var tasks = [ImageTask]()
        
        init(dataTask: NSURLSessionDataTask) {
            self.dataTask = dataTask
        }
    }
}

class ImageSessionTaskKey: Hashable {
    let request: ImageRequest
    var hashValue: Int {
        return self.request.URL.hashValue
    }
    
    init(_ request: ImageRequest) {
        self.request = request
    }
}

func ==(lhs: ImageSessionTaskKey, rhs: ImageSessionTaskKey) -> Bool {
    // TODO: Add more stuff, when options are extended with additional properties
    return lhs.request.URL == rhs.request.URL
}
