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
    public let sessionManager: URLSessionManager
    let queue = dispatch_queue_create("ImageManager-InternalSerialQueue", DISPATCH_QUEUE_SERIAL)
    var sessionTasks = [ImageSessionTaskKey: ImageSessionTask]()
    
    public init(sessionManager: URLSessionManager) {
        self.sessionManager = sessionManager
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
    
    func resumeImageTask(task: ImageTaskInternal) {
        // TODO: Cache lookup
        dispatch_async(self.queue) {
            self.executeImageTask(task)
        }
    }
    
    func executeImageTask(imageTask: ImageTaskInternal) {
        let sessionTaskKey = ImageSessionTaskKey(imageTask.request)
        var sessionTask: ImageSessionTask! = self.sessionTasks[sessionTaskKey]
        if sessionTask == nil {
            sessionTask = ImageSessionTask(key: sessionTaskKey)
            let URLRequest = NSURLRequest(URL: imageTask.request.URL)
            sessionTask.dataTask = self.sessionManager.dataTaskWithRequest(URLRequest) { [weak self] (data: NSData?, _, error: NSError?) -> Void in
                self?.dataTaskDidComplete(sessionTask, data: data, error: error)
                return
            }
            self.sessionTasks[sessionTaskKey] = sessionTask
            sessionTask.dataTask.resume() // TODO: Resume only when necessary
        }
        sessionTask.imageTasks.insert(imageTask)
        imageTask.sessionTask = sessionTask // we will break the retain cycle later
    }
    
    func dataTaskDidComplete(sessionTask: ImageSessionTask,  data: NSData!, error: NSError!) {
        dispatch_async(self.queue) {
            let image = data != nil ? UIImage(data: data, scale: UIScreen.mainScreen().scale) : nil
            for imageTask in sessionTask.imageTasks {
                dispatch_async(dispatch_get_main_queue()) {
                    imageTask.completionHandler?(ImageResponse(image: image))
                }
            }
            sessionTask.imageTasks.removeAll(keepCapacity: false)
        }
    }
    
    func cancelImageTask(imageTask: ImageTaskInternal) {
        dispatch_async(self.queue) {
            // TODO: Set task state
            if let sessionTask = imageTask.sessionTask {
                sessionTask.imageTasks.remove(imageTask)
                if sessionTask.imageTasks.count == 0 {
                    sessionTask.dataTask.cancel()
                    self.sessionTasks.removeValueForKey(sessionTask.key)
                }
            }
            // TODO: Cancel processing operation (when it's implemented)
        }
    }
    
    class ImageTaskInternal: ImageTask {
        var sessionTask: ImageSessionTask?
        
        // TODO: Make weak?
        let manager: ImageManager
        
        init(manager: ImageManager, request: ImageRequest, completionHandler: ImageCompletionHandler?) {
            self.manager = manager
            super.init(request: request, completionHandler: completionHandler)
        }
        
        override func resume() -> Self {
            self.manager.resumeImageTask(self)
            return self
        }
        
        override func cancel() {
            self.manager.cancelImageTask(self)
        }
    }
    
    class ImageSessionTask {
        var dataTask: NSURLSessionDataTask!
        let key: ImageSessionTaskKey
        var imageTasks = Set<ImageTaskInternal>()
        
        init(key: ImageSessionTaskKey) {
            self.key = key
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
