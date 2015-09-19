// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import UIKit

// MARK: ImageDataLoading

public typealias ImageDataLoadingCompletionHandler = (data: NSData?, response: NSURLResponse?, error: ErrorType?) -> Void
public typealias ImageDataLoadingProgressHandler = (completedUnitCount: Int64, totalUnitCount: Int64) -> Void

public protocol ImageDataLoading {
    /** Compares two requests for equivalence with regard to loading image data. Requests should be considered equivalent if the image fetcher can handle both requests with a single data task.
    */
    func isRequestLoadEquivalent(lhs: ImageRequest, toRequest rhs: ImageRequest) -> Bool
    
    /** Compares two requests for equivalence with regard to caching image data. ImageManager  uses this method for memory caching only, which means that there is no need for filtering out the dynamic part of the request (is there is any).
    */
    func isRequestCacheEquivalent(lhs: ImageRequest, toRequest rhs: ImageRequest) -> Bool
    
    /** Creates image data task with a given url
    */
    func imageDataTaskWithURL(url: NSURL, progressHandler: ImageDataLoadingProgressHandler, completionHandler: ImageDataLoadingCompletionHandler) -> NSURLSessionDataTask
    
    /** Invalidates the receiver
    */
    func invalidate()
    
    func removeAllCachedImages()
}


// MARK: ImageDataLoader

public class ImageDataLoader: NSObject, NSURLSessionDataDelegate, ImageDataLoading {
    public private(set) var session: NSURLSession!
    private var taskHandlers = [NSURLSessionTask: URLSessionDataTaskHandler]()
    private let queue = dispatch_queue_create("ImageDataLoader-InternalSerialQueue", DISPATCH_QUEUE_SERIAL)
    
    public init(sessionConfiguration: NSURLSessionConfiguration) {
        super.init()
        self.session = NSURLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }
    
    public convenience override init() {
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        configuration.URLCache = NSURLCache(memoryCapacity: 0, diskCapacity: 200 * 1024 * 1024, diskPath: "com.github.kean.nuke-image-cache")
        configuration.timeoutIntervalForRequest = 60.0
        configuration.timeoutIntervalForResource = 360.0
        self.init(sessionConfiguration: configuration)
    }
    
    // MARK: ImageDataLoading
    
    public func isRequestLoadEquivalent(lhs: ImageRequest, toRequest rhs: ImageRequest) -> Bool {
        return lhs.URL.isEqual(rhs.URL)
    }
    
    public func isRequestCacheEquivalent(lhs: ImageRequest, toRequest rhs: ImageRequest) -> Bool {
        return lhs.URL.isEqual(rhs.URL)
    }
    
    public func imageDataTaskWithURL(URL: NSURL, progressHandler: ImageDataLoadingProgressHandler, completionHandler: ImageDataLoadingCompletionHandler) -> NSURLSessionDataTask {
        let dataTask = self.session.dataTaskWithURL(URL)
        dispatch_sync(self.queue) {
            self.taskHandlers[dataTask] = URLSessionDataTaskHandler(progressHandler: progressHandler, completionHandler: completionHandler)
        }
        return dataTask
    }
    
    public func invalidate() {
        self.session.invalidateAndCancel()
    }
    
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
