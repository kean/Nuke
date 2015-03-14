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
    var tasks = [ImageRequestFetchKey: ImageTaskInternal]()
    
    public init() {
        
    }
    
    public func imageTaskWithRequest(request: ImageRequest, completionHandler: ImageCompletionHandler?) -> ImageTask {
        // TODO: Create canonical request
        return ImageTask(manager: self, request: request, completionHandler: completionHandler)
    }
    
    public func startPreheatingImages(requests: [ImageRequest]) {
        
    }
    
    public func stopPreheatingImages(request: [ImageRequest]) {
        
    }
    
    public func stopPreheatingImages() {
        
    }
    
    func resumeTask(task: ImageTask) {
        // TODO: Cache lookup
        dispatch_async(self.queue) {
            let requestKey = ImageRequestFetchKey(task.request)
            var internalTask = self.tasks[requestKey]
            if internalTask == nil {
                internalTask = ImageTaskInternal(request: task.request, key: requestKey)
                // TODO: Configure task for execution
                self.tasks[requestKey] = internalTask
            }
            // TODO: Add handler and execute
        }
    }
    
    func cancelTask(task: ImageTask) {
        dispatch_async(self.queue) {
            // TODO: Find internal task
        }
    }
}

class ImageRequestFetchKey: Hashable {
    let request: ImageRequest
    var hashValue: Int {
        return self.request.URL.hashValue
    }
    
    init(_ request: ImageRequest) {
        self.request = request
    }
}

func ==(lhs: ImageRequestFetchKey, rhs: ImageRequestFetchKey) -> Bool {
    // TODO: Add more stuff, when options are extended with additional properties
    return lhs.request.URL == rhs.request.URL
}
