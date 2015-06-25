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

#if WATCHKIT
  import WatchKit
  #else
  import Foundation
#endif

public typealias URLSessionManagerCompletionHandler = (data: NSData?, response: NSURLResponse?, error: NSError?) -> Void
public typealias URLSessionManagerProgressHandler = (progress: Double) -> Void

public class URLSessionManager: NSObject, NSURLSessionDataDelegate {
    public private(set) var session: NSURLSession!
    private var taskHandlers = [NSURLSessionTask: URLSessionDataTaskHandler]()
    private let queue = dispatch_queue_create("URLSessionManager-InternalSerialQueue", DISPATCH_QUEUE_SERIAL)
    
    public init(sessionConfiguration: NSURLSessionConfiguration) {
        super.init()
        self.session = NSURLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }
    
    public convenience override init() {
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        configuration.URLCache = NSURLCache(memoryCapacity: 0, diskCapacity: 256 * 1024 * 1024, diskPath: "com.github.kean.nuke-image-cache")
        configuration.timeoutIntervalForRequest = 60.0
        configuration.timeoutIntervalForResource = 360.0
        self.init(sessionConfiguration: configuration)
    }
    
    public func dataTaskWithRequest(request: NSURLRequest, progressHandler: URLSessionManagerProgressHandler?, completionHandler: URLSessionManagerCompletionHandler) -> NSURLSessionDataTask {
        let dataTask = self.session.dataTaskWithRequest(request)
        dispatch_sync(self.queue) {
            self.taskHandlers[dataTask!] = URLSessionDataTaskHandler(progressHandler: progressHandler, completionHandler: completionHandler)
        }
        return dataTask!
    }
    
    public func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
        dispatch_sync(self.queue) {
            if let handler = self.taskHandlers[dataTask] {
                handler.data.appendData(data)
                let progress = Double(dataTask.countOfBytesReceived) / Double(dataTask.countOfBytesExpectedToReceive)
                handler.progressHandler?(progress: progress)
            }
        }
    }
    
    public func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
        dispatch_sync(self.queue) {
            if let handler = self.taskHandlers[task] {
                handler.completionHandler(data: handler.data, response: task.response, error: error)
                self.taskHandlers.removeValueForKey(task)
            }
        }
    }
}

private class URLSessionDataTaskHandler {
    let data = NSMutableData()
    let progressHandler: URLSessionManagerProgressHandler?
    let completionHandler: URLSessionManagerCompletionHandler
    
    init(progressHandler: URLSessionManagerProgressHandler?, completionHandler: URLSessionManagerCompletionHandler) {
        self.progressHandler = progressHandler
        self.completionHandler = completionHandler
    }
}
