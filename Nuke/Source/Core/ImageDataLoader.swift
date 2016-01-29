// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageDataLoading

public typealias ImageDataLoadingCompletionHandler = (data: NSData?, response: NSURLResponse?, error: ErrorType?) -> Void
public typealias ImageDataLoadingProgressHandler = (completedUnitCount: Int64, totalUnitCount: Int64) -> Void

/** Performs loading of image data.
 */
public protocol ImageDataLoading {
    func imageDataTaskWithRequest(request: ImageRequest, progressHandler: ImageDataLoadingProgressHandler, completionHandler: ImageDataLoadingCompletionHandler) -> NSURLSessionTask
    
    func invalidate()
    
    func removeAllCachedImages()
}


// MARK: - ImageDataLoader

/** Provides basic networking using NSURLSession.
*/
public class ImageDataLoader: NSObject, NSURLSessionDataDelegate, ImageDataLoading {
    public private(set) var session: NSURLSession!
    private var taskHandlers = [NSURLSessionTask: URLSessionDataTaskHandler]()
    private let queue = dispatch_queue_create("ImageDataLoader-InternalSerialQueue", DISPATCH_QUEUE_SERIAL)
    
    public init(sessionConfiguration: NSURLSessionConfiguration) {
        super.init()
        self.session = NSURLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }

    /** Initializes the receiver with a default NSURLSession configuration. 
     
     The memory capacity of the NSURLCache is set to 0, disk capacity is set to 200 Mb.
     */
    public convenience override init() {
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        configuration.URLCache = NSURLCache(memoryCapacity: 0, diskCapacity: 200 * 1024 * 1024, diskPath: "com.github.kean.nuke-image-cache")
        configuration.timeoutIntervalForRequest = 60.0
        configuration.timeoutIntervalForResource = 360.0
        self.init(sessionConfiguration: configuration)
    }
    
    // MARK: ImageDataLoading
    
    public func imageDataTaskWithRequest(request: ImageRequest, progressHandler: ImageDataLoadingProgressHandler, completionHandler: ImageDataLoadingCompletionHandler) -> NSURLSessionTask {
        let task = self.createTaskWithRequest(request)
        dispatch_sync(self.queue) {
            self.taskHandlers[task] = URLSessionDataTaskHandler(progressHandler: progressHandler, completionHandler: completionHandler)
        }
        return task
    }
    
    /** Factory method for creating session tasks for given image requests.
     */
    public func createTaskWithRequest(request: ImageRequest) -> NSURLSessionTask {
        return self.session.dataTaskWithRequest(request.URLRequest)
    }

    /** Invalidates the instance of NSURLSession class that the receiver was initialized with.
     */
    public func invalidate() {
        self.session.invalidateAndCancel()
    }

    /** Removes all cached images from the instance of NSURLCache class from the NSURLSession configuration.
     */
    public func removeAllCachedImages() {
        self.session.configuration.URLCache?.removeAllCachedResponses()
    }
    
    // MARK: NSURLSessionDataDelegate
    
    public func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
        dispatch_sync(self.queue) {
            if let handler = self.taskHandlers[dataTask] {
                handler.data.appendData(data)
                handler.progressHandler(completedUnitCount: dataTask.countOfBytesReceived, totalUnitCount: dataTask.countOfBytesExpectedToReceive)
            }
        }
    }
    
    public func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
        dispatch_sync(self.queue) {
            if let handler = self.taskHandlers[task] {
                handler.completionHandler(data: handler.data, response: task.response, error: error)
                self.taskHandlers[task] = nil
            }
        }
    }
}

private class URLSessionDataTaskHandler {
    let data = NSMutableData()
    let progressHandler: ImageDataLoadingProgressHandler
    let completionHandler: ImageDataLoadingCompletionHandler
    
    init(progressHandler: ImageDataLoadingProgressHandler, completionHandler: ImageDataLoadingCompletionHandler) {
        self.progressHandler = progressHandler
        self.completionHandler = completionHandler
    }
}
