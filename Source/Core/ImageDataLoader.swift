// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageDataLoading

/// Data loading completion closure.
public typealias ImageDataLoadingCompletion = (data: NSData?, response: NSURLResponse?, error: ErrorType?) -> Void

/// Data loading progress closure.
public typealias ImageDataLoadingProgress = (completed: Int64, total: Int64) -> Void

/// Performs loading of image data.
public protocol ImageDataLoading {
    /// Creates task with a given request. Task is resumed by the object calling the method.
    func taskWith(request: ImageRequest, progress: ImageDataLoadingProgress, completion: ImageDataLoadingCompletion) -> NSURLSessionTask

    /// Invalidates the receiver.
    func invalidate()

    /// Clears the receiver's cache storage (in any).
    func removeAllCachedImages()
}


// MARK: - ImageDataLoader

/// Provides basic networking using NSURLSession.
public class ImageDataLoader: NSObject, NSURLSessionDataDelegate, ImageDataLoading {
    public private(set) var session: NSURLSession!
    private var handlers = [NSURLSessionTask: DataTaskHandler]()
    private let queue = dispatch_queue_create("ImageDataLoader.Queue", DISPATCH_QUEUE_SERIAL)

    /** Initialzies data loader by creating a session with a given session configuration. Data loader is set as a delegate of the session.
     */
    public init(sessionConfiguration: NSURLSessionConfiguration) {
        super.init()
        self.session = NSURLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
    }

    /**
     Initializes the receiver with a default NSURLSession configuration.

     The memory capacity of the NSURLCache is set to 0, disk capacity is set to 200 Mb.
     */
    public convenience override init() {
        let conf = NSURLSessionConfiguration.defaultSessionConfiguration()
        conf.URLCache = NSURLCache(memoryCapacity: 0, diskCapacity: (200 * 1024 * 1024), diskPath: "com.github.kean.nuke-cache")
        conf.timeoutIntervalForRequest = 60.0
        conf.timeoutIntervalForResource = 360.0
        self.init(sessionConfiguration: conf)
    }
    
    // MARK: ImageDataLoading

    /// Creates task for the given request.
    public func taskWith(request: ImageRequest, progress: ImageDataLoadingProgress, completion: ImageDataLoadingCompletion) -> NSURLSessionTask {
        let task = self.taskWith(request)
        dispatch_sync(queue) {
            self.handlers[task] = DataTaskHandler(progress: progress, completion: completion)
        }
        return task
    }
    
    /// Factory method for creating session tasks for given image requests.
    public func taskWith(request: ImageRequest) -> NSURLSessionTask {
        return session.dataTaskWithRequest(request.URLRequest)
    }

    /// Invalidates the instance of NSURLSession class that the receiver was initialized with.
    public func invalidate() {
        session.invalidateAndCancel()
    }

    /// Removes all cached images from the instance of NSURLCache class from the NSURLSession configuration.
    public func removeAllCachedImages() {
        session.configuration.URLCache?.removeAllCachedResponses()
    }
    
    // MARK: NSURLSessionDataDelegate
    
    public func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
        dispatch_sync(queue) {
            if let handler = self.handlers[dataTask] {
                handler.data.appendData(data)
                handler.progress(completed: dataTask.countOfBytesReceived, total: dataTask.countOfBytesExpectedToReceive)
            }
        }
    }
    
    public func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
        dispatch_sync(queue) {
            if let handler = self.handlers[task] {
                handler.completion(data: handler.data, response: task.response, error: error)
                self.handlers[task] = nil
            }
        }
    }
}

private class DataTaskHandler {
    let data = NSMutableData()
    let progress: ImageDataLoadingProgress
    let completion: ImageDataLoadingCompletion
    
    init(progress: ImageDataLoadingProgress, completion: ImageDataLoadingCompletion) {
        self.progress = progress
        self.completion = completion
    }
}
