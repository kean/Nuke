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

public let ImageMaximumSize = CGSizeMake(CGFloat.max, CGFloat.max)

public typealias ImageCompletionHandler = (ImageResponse) -> Void

public let ImageManagerErrorDomain = "Nuke.ImageManagerErrorDomain"
public let ImageManagerErrorCancelled = -1

// MARK: - ImageManagerConfiguration -

public struct ImageManagerConfiguration {
    public var sessionManager: URLSessionManager
    public var cache: ImageMemoryCache?
    
    public init(sessionManager: URLSessionManager, cache: ImageMemoryCache? = ImageMemoryCache()) {
        self.sessionManager = sessionManager
        self.cache = cache
    }
}

// MARK: - ImageManager -

public class ImageManager {
    public let configuration: ImageManagerConfiguration
    private let sessionManager: URLSessionManager
    private let queue = dispatch_queue_create("ImageManager-InternalSerialQueue", DISPATCH_QUEUE_SERIAL)
    
    private var sessionTasks = [ImageSessionTaskKey: ImageSessionTask]()
    
    public init(configuration: ImageManagerConfiguration) {
        self.configuration = configuration
        self.sessionManager = configuration.sessionManager
    }
    
    public func imageTaskWithRequest(request: ImageRequest, completionHandler: ImageCompletionHandler?) -> ImageTask {
        return ImageTaskInternal(manager: self, request: request, completionHandler: completionHandler)
    }
    
    public func startPreheatingImages(requests: [ImageRequest]) {
        
    }
    
    public func stopPreheatingImages(request: [ImageRequest]) {
        
    }
    
    public func stopPreheatingImages() {
        
    }
    
    public func invalidateAndCancel() {
        
    }
    
    private func resumeImageTask(task: ImageTaskInternal) {
        dispatch_sync(self.queue) {
            self.setTaskState(.Running, task: task)
        }
    }
    
    private func cancelImageTask(task: ImageTaskInternal) {
        dispatch_sync(self.queue) {
            self.setTaskState(.Cancelled, task: task)
        }
    }
    
    private func setTaskState(state: ImageTaskState, task: ImageTaskInternal)  {
        if self.transitionAllowed(task.state, toState: state) {
            self.transitionStateAction(task.state, toState: state, task: task)
            task.state = state
            self.enterStateAction(state, task: task)
        }
    }
    
    private static let transitions: [ImageTaskState: [ImageTaskState]] = [
        .Suspended: [.Running, .Cancelled],
        .Running: [.Completed, .Cancelled]
    ]
    
    private func transitionAllowed(fromState: ImageTaskState, toState: ImageTaskState) -> Bool {
        if let toStates = ImageManager.transitions[fromState] {
            return contains(toStates, toState)
        }
        return false
    }
    
    private func transitionStateAction(fromState: ImageTaskState, toState: ImageTaskState, task: ImageTaskInternal) {
        if (fromState == .Running && toState == .Cancelled) {
            if let sessionTask = task.sessionTask {
                sessionTask.imageTasks.remove(task)
                if sessionTask.imageTasks.count == 0 {
                    sessionTask.dataTask.cancel()
                    self.sessionTasks.removeValueForKey(sessionTask.key)
                }
            }
        }
    }
    
    private func enterStateAction(state: ImageTaskState, task: ImageTaskInternal) {
        switch state {
            
        case .Running:
            let sessionTaskKey = ImageSessionTaskKey(task.request)
            var sessionTask: ImageSessionTask! = self.sessionTasks[sessionTaskKey]
            if sessionTask == nil {
                sessionTask = ImageSessionTask(key: sessionTaskKey)
                let URLRequest = NSURLRequest(URL: task.request.URL)
                sessionTask.dataTask = self.sessionManager.dataTaskWithRequest(URLRequest) { [weak self] (data: NSData?, _, error: NSError?) -> Void in
                    self?.didCompleteDataTask(sessionTask, data: data, error: error)
                    return
                }
                self.sessionTasks[sessionTaskKey] = sessionTask
                sessionTask.dataTask.resume()
            }
            sessionTask.imageTasks.insert(task)
            task.sessionTask = sessionTask // retain cycle is broken later
            
        case .Cancelled:
            dispatch_async(dispatch_get_main_queue()) {
                let error = NSError(domain: ImageManagerErrorDomain, code: ImageManagerErrorCancelled, userInfo: nil)
                task.completionHandler?(ImageResponse(image: nil, error: error))
            }
            
        case .Completed:
            dispatch_async(dispatch_get_main_queue()) {
                task.completionHandler?(task.response ?? ImageResponse())
            }
            
        default:
            return
        }
    }
    
    private func didCompleteDataTask(sessionTask: ImageSessionTask,  data: NSData!, error: NSError!) {
        dispatch_sync(self.queue) {
            let image = data != nil ? UIImage(data: data, scale: UIScreen.mainScreen().scale) : nil
            let response = ImageResponse(image: image, error: error)
            for imageTask in sessionTask.imageTasks {
                imageTask.sessionTask = nil
                imageTask.response = response
                self.setTaskState(.Completed, task: imageTask)
            }
            sessionTask.imageTasks.removeAll(keepCapacity: false)
        }
    }
    
    // MARK: ImageTaskInternal
    
    enum ImageTaskState {
        case Suspended
        case Running
        case Cancelled
        case Completed
    }
    
    class ImageTaskInternal: ImageTask {
        var sessionTask: ImageSessionTask?
        let manager: ImageManager
        var state = ImageTaskState.Suspended
        
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
    
    // MARK: ImageSessionTask
    
    class ImageSessionTask {
        var dataTask: NSURLSessionDataTask!
        let key: ImageSessionTaskKey
        var imageTasks = Set<ImageTaskInternal>()
        
        init(key: ImageSessionTaskKey) {
            self.key = key
        }
    }
}

// MARK: - ImageSessionTaskKey -

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
