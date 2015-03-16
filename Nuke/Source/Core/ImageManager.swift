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
    public var processor: ImageProcessing?
    
    public init(sessionManager: URLSessionManager, cache: ImageMemoryCache?, processor: ImageProcessing?) {
        self.sessionManager = sessionManager
        self.cache = cache
        self.processor = processor
    }
}

// MARK: - ImageManager -

public class ImageManager {
    public let configuration: ImageManagerConfiguration
    private let sessionManager: URLSessionManager
    private let queue = dispatch_queue_create("ImageManager-InternalSerialQueue", DISPATCH_QUEUE_SERIAL)
    private let processingQueue: NSOperationQueue
    private var dataTasks = [ImageRequestKey: ImageDataTask]()
    
    public init(configuration: ImageManagerConfiguration) {
        self.configuration = configuration
        self.sessionManager = configuration.sessionManager
        self.processingQueue = NSOperationQueue()
        self.processingQueue.maxConcurrentOperationCount = 2
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
            if let dataTask = task.dataTask {
                dataTask.imageTasks.remove(task)
                if dataTask.imageTasks.count == 0 {
                    dataTask.sessionTask.cancel()
                    self.dataTasks.removeValueForKey(dataTask.key)
                }
            }
            task.processingOperation?.cancel()
        }
    }
    
    private func enterStateAction(state: ImageTaskState, task: ImageTaskInternal) {
        switch state {
            
        case .Running:
            if let image = self.configuration.cache?.cachedImage(ImageRequestKey(task.request, type: .Cache, owner: self)) {
                task.response = ImageResponse(image: image, error: nil)
                self.setTaskState(.Completed, task: task)
            } else {
                let dataTaskKey = ImageRequestKey(task.request, type: .Fetch, owner: self)
                var dataTask: ImageDataTask! = self.dataTasks[dataTaskKey]
                if dataTask == nil {
                    dataTask = ImageDataTask(request: task.request, key: dataTaskKey)
                    let URLRequest = NSURLRequest(URL: task.request.URL)
                    dataTask.sessionTask = self.sessionManager.dataTaskWithRequest(URLRequest) { [weak self] (data: NSData?, _, error: NSError?) -> Void in
                        self?.didCompleteDataTask(dataTask, data: data, error: error)
                        return
                    }
                    self.dataTasks[dataTaskKey] = dataTask
                    dataTask.sessionTask.resume()
                }
                dataTask.imageTasks.insert(task)
                task.dataTask = dataTask
            }
            
        case .Cancelled:
            dispatch_async(dispatch_get_main_queue()) {
                let error = NSError(domain: ImageManagerErrorDomain, code: ImageManagerErrorCancelled, userInfo: nil)
                task.completionHandler?(ImageResponse(image: nil, error: error))
            }
            
        case .Completed:
            let block: dispatch_block_t = {
                task.completionHandler?(task.response ?? ImageResponse())
            }
            NSThread.isMainThread() ? block() : dispatch_async(dispatch_get_main_queue(), block)
            
        default:
            return
        }
    }
    
    private func didCompleteDataTask(dataTask: ImageDataTask, data: NSData!, error: NSError!) {
        dispatch_sync(self.queue) {
            let image = data != nil ? UIImage(data: data, scale: UIScreen.mainScreen().scale) : nil
            for imageTask in dataTask.imageTasks {
                imageTask.dataTask = nil
                if image != nil {
                    self.processImage(image!, imageTask: imageTask) {
                        (processedImage: UIImage) -> Void in
                        imageTask.response = ImageResponse(image: processedImage, error: nil)
                        dispatch_sync(self.queue) {
                            self.setTaskState(.Completed, task: imageTask)
                        }
                    }
                } else {
                    imageTask.response = ImageResponse(image: nil, error: error)
                    self.setTaskState(.Completed, task: imageTask)
                }
            }
            dataTask.imageTasks.removeAll(keepCapacity: false)
            self.dataTasks.removeValueForKey(dataTask.key)
        }
    }
    
    private func processImage(image: UIImage, imageTask: ImageTaskInternal, completionHandler: (processedImage: UIImage) -> Void) {
        let cacheKey = ImageRequestKey(imageTask.request, type: .Cache, owner: self)
        let cache = self.configuration.cache
        if let processor = self.configuration.processor {
            let operation = NSBlockOperation() {
                if let processedImage = cache?.cachedImage(cacheKey) {
                    completionHandler(processedImage: processedImage)
                } else {
                    let processedImage = processor.processedImage(image, request: imageTask.request)
                    cache?.storeImage(processedImage, key: cacheKey)
                    completionHandler(processedImage: processedImage)
                }
            }
            self.processingQueue.addOperation(operation)
        } else {
            cache?.storeImage(image, key: cacheKey)
            dispatch_async(dispatch_get_main_queue()) {
                completionHandler(processedImage: image)
            }
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
        weak var dataTask: ImageDataTask?
        weak var processingOperation: NSOperation?
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
    
    // MARK: ImageDataTask
    
    class ImageDataTask {
        var sessionTask: NSURLSessionDataTask!
        let request: ImageRequest
        private let key: ImageRequestKey
        var imageTasks = Set<ImageTaskInternal>()
        
        private init(request: ImageRequest, key: ImageRequestKey) {
            self.request = request
            self.key = key
        }
    }
}


extension ImageManager: ImageRequestKeyOwner {
    private func isImageRequestKey(key: ImageRequestKey, equalToKey key2: ImageRequestKey) -> Bool {
        if (key.type == .Cache) {
            if let processor = self.configuration.processor {
                if !(processor.isProcessingEquivalent(key.request, r2: key2.request)) {
                    return false
                }
            }
        }
        return key.request.URL.isEqual(key2.request.URL)
    }
}


// MARK: - ImageRequestKey -

private protocol ImageRequestKeyOwner: class {
    func isImageRequestKey(key: ImageRequestKey, equalToKey: ImageRequestKey) -> Bool
}

private enum ImageRequestKeyType {
    case Fetch
    case Cache
}

/** Makes it possible to use ImageRequest as a key in dictionaries (and dictionary-like structures). This should be a nested class inside ImageManager but it's impossible because of the Equatable protocol.
*/
private class ImageRequestKey: NSObject, Hashable {
    let request: ImageRequest
    let type: ImageRequestKeyType
    weak var owner: ImageRequestKeyOwner?
    override var hashValue: Int {
        return self.request.URL.hashValue
    }
    
    init(_ request: ImageRequest, type: ImageRequestKeyType, owner: ImageRequestKeyOwner?) {
        self.request = request
        self.type = type
        self.owner = owner
    }
    
    // Make it possible to use ImageRequesKey as key in NSCache
    override var hash: Int {
        return self.hashValue
    }
    private override func isEqual(object: AnyObject?) -> Bool {
        if object === self {
            return true
        }
        if let object = object as? ImageRequestKey {
            return self == object
        }
        return false
    }
}

private func ==(lhs: ImageRequestKey, rhs: ImageRequestKey) -> Bool {
    if let owner = lhs.owner where lhs.owner === rhs.owner && lhs.type == rhs.type {
        return owner.isImageRequestKey(lhs, equalToKey: rhs)
    }
    return false
}
