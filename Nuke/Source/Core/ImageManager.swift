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

public typealias ImageCompletionHandler = (image: UIImage?, error: NSError?) -> Void

public let ImageManagerErrorDomain = "Nuke.ImageManagerErrorDomain"
public let ImageManagerErrorCancelled = -1

// MARK: - ImageManagerConfiguration -

public struct ImageManagerConfiguration {
    public var sessionManager: URLSessionManager
    public var cache: ImageMemoryCaching?
    public var processor: ImageProcessing?
    public var maxConcurrentPreheatingRequests = 2
    
    public init(sessionManager: URLSessionManager, cache: ImageMemoryCaching?, processor: ImageProcessing?) {
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
    
    private var executingImageTasks = Set<ImageTaskInternal>()
    private var dataTasks = [ImageRequestKey: ImageDataTask]()
    
    private var preheatingTasks = [ImageRequestKey: ImageTaskInternal]()
    private var needsToExecutePreheatingTasks = false
    
    public init(configuration: ImageManagerConfiguration) {
        self.configuration = configuration
        self.sessionManager = configuration.sessionManager
        self.processingQueue = NSOperationQueue()
        self.processingQueue.maxConcurrentOperationCount = 2
    }
    
    public func imageTaskWithURL(URL: NSURL, completionHandler: ImageCompletionHandler?) -> ImageTask {
        return self.imageTaskWithRequest(ImageRequest(URL: URL), completionHandler: completionHandler)
    }
    
    public func imageTaskWithRequest(request: ImageRequest, completionHandler: ImageCompletionHandler?) -> ImageTask {
        return ImageTaskInternal(manager: self, request: request, completionHandler: completionHandler)
    }
    
    public func invalidateAndCancel() {
        for task in executingImageTasks {
            self.setTaskState(.Cancelled, task: task)
        }
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
        let completeTask = { () -> Void in
            self.executingImageTasks.remove(task)
            self.setNeedsExecutePreheatingTasks()
            
            let block: dispatch_block_t = {
                task.completionHandler?(image: task.image, error: task.error)
            }
            NSThread.isMainThread() ? block() : dispatch_async(dispatch_get_main_queue(), block)
        }
        
        switch state {
            
        case .Running:
            self.executingImageTasks.insert(task)
            
            if let image = self.configuration.cache?.cachedImage(ImageRequestKey(task.request, type: .Cache, owner: self)) {
                task.image = image
                self.setTaskState(.Completed, task: task)
            } else {
                self.startDataTaskForImageTask(task)
            }
            
        case .Cancelled:
            task.error = NSError(domain: ImageManagerErrorDomain, code: ImageManagerErrorCancelled, userInfo: nil)
            completeTask()
            
        case .Completed:
            completeTask()
            
        default:
            return
        }
    }
    
    private func startDataTaskForImageTask(task: ImageTaskInternal) {
        let dataTaskKey = ImageRequestKey(task.request, type: .Fetch, owner: self)
        var dataTask: ImageDataTask! = self.dataTasks[dataTaskKey]
        if dataTask == nil {
            dataTask = ImageDataTask(request: task.request, key: dataTaskKey)
            let URLRequest = NSURLRequest(URL: task.request.URL)
            dataTask.sessionTask = self.sessionManager.dataTaskWithRequest(URLRequest,
                progressHandler: { [weak dataTask] (progress) -> Void in
                    if let imageTasks = dataTask?.imageTasks {
                        for imageTask in imageTasks {
                            dispatch_async(dispatch_get_main_queue()) {
                                imageTask.request.progressHandler?(progress: progress)
                            }
                        }
                    }
                }, completionHandler: { [weak self] (data, response, error) -> Void in
                    self?.didCompleteDataTask(dataTask, data: data, error: error)
                    return
                })
            self.dataTasks[dataTaskKey] = dataTask
            dataTask.sessionTask.resume()
        }
        dataTask.imageTasks.insert(task)
        task.dataTask = dataTask
    }
    
    private func didCompleteDataTask(dataTask: ImageDataTask, data: NSData!, error: NSError!) {
        dispatch_sync(self.queue) {
            let image = data != nil ? UIImage(data: data, scale: UIScreen.mainScreen().scale) : nil
            for imageTask in dataTask.imageTasks {
                imageTask.dataTask = nil
                if image != nil {
                    self.processImage(image!, imageTask: imageTask) {
                        (processedImage: UIImage) -> Void in
                        imageTask.image = processedImage
                        dispatch_sync(self.queue) {
                            self.setTaskState(.Completed, task: imageTask)
                        }
                    }
                } else {
                    imageTask.error = error
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
    
    // MARK: Preheating
    
    public func startPreheatingImages(requests: [ImageRequest]) {
        dispatch_sync(self.queue) {
            for request in requests {
                let key = ImageRequestKey(request, type: .Cache, owner: self)
                if self.preheatingTasks[key] == nil {
                    let task = ImageTaskInternal(manager: self, request: request) { [weak self] (response) -> Void in
                        self?.preheatingTasks.removeValueForKey(key)
                        return
                    }
                    self.preheatingTasks[key] = task
                }
            }
            self.setNeedsExecutePreheatingTasks()
        }
    }
    
    public func stopPreheatingImages(requests: [ImageRequest]) {
        dispatch_sync(self.queue) {
            for request in requests {
                let key = ImageRequestKey(request, type: .Cache, owner: self)
                if let task = self.preheatingTasks[key] {
                    self.setTaskState(.Cancelled, task: task)
                    self.preheatingTasks.removeValueForKey(key)
                }
            }
        }
    }
    
    public func stopPreheatingImages() {
        dispatch_sync(self.queue) {
            for (key, task) in self.preheatingTasks {
                self.setTaskState(.Cancelled, task: task)
            }
            self.preheatingTasks.removeAll(keepCapacity: false)
        }
    }
    
    private func setNeedsExecutePreheatingTasks() {
        if !self.needsToExecutePreheatingTasks {
            self.needsToExecutePreheatingTasks = true
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64((0.1 * Double(NSEC_PER_SEC)))), self.queue) {
                [weak self] in self?.executePreheatingTasksIfNeeded(); return
            }
        }
    }
    
    private func executePreheatingTasksIfNeeded() {
        var executingTaskCount = self.executingImageTasks.count
        for (key, task) in self.preheatingTasks {
            if executingTaskCount > self.configuration.maxConcurrentPreheatingRequests {
                break;
            }
            if task.state == .Suspended {
                self.setTaskState(.Running, task: task)
                executingTaskCount++
            }
        }
    }
}


extension ImageManager: ImageRequestKeyOwner {
    private func isImageRequestKey(key: ImageRequestKey, equalToKey key2: ImageRequestKey) -> Bool {
        switch key.type {
        case .Cache:
            if !key.request.URL.isEqual(key2.request.URL) {
                return false
            }
            if let processor = self.configuration.processor {
                if !(processor.isProcessingEquivalent(key.request, r2: key2.request)) {
                    return false
                }
            }
            return true
        case .Fetch:
            return key.request.URL.isEqual(key2.request.URL)
        }
    }
}


// Shared manager
extension ImageManager {
    private static var sharedManagerIvar: ImageManager!
    private static var lock = OS_SPINLOCK_INIT
    private static var token: dispatch_once_t = 0
    
    public class func sharedManager() -> ImageManager {
        var manager: ImageManager
        dispatch_once(&token) {
            if self.sharedManagerIvar == nil {
                let conf = ImageManagerConfiguration(sessionManager: URLSessionManager(), cache: ImageMemoryCache(), processor: ImageProcessor())
                self.sharedManagerIvar = ImageManager(configuration: conf)
            }
        }
        OSSpinLockLock(&lock)
        manager = sharedManagerIvar
        OSSpinLockUnlock(&lock)
        return manager
    }
    
    public class func setSharedManager(manager: ImageManager) {
        OSSpinLockLock(&lock)
        sharedManagerIvar = manager
        OSSpinLockUnlock(&lock)
    }
}


// MARK: - ImageTaskInternal -

private class ImageTaskInternal: ImageTask {
    weak var dataTask: ImageDataTask?
    weak var processingOperation: NSOperation?
    let manager: ImageManager
    
    init(manager: ImageManager, request: ImageRequest, completionHandler: ImageCompletionHandler?) {
        self.manager = manager
        super.init(request: request, completionHandler: completionHandler)
    }
    
    override func resume() {
        self.manager.resumeImageTask(self)
    }
    
    override func cancel() {
        self.manager.cancelImageTask(self)
    }
}


// MARK: - ImageDataTask -

private class ImageDataTask {
    var sessionTask: NSURLSessionDataTask!
    let request: ImageRequest
    private let key: ImageRequestKey
    var imageTasks = Set<ImageTaskInternal>()
    
    private init(request: ImageRequest, key: ImageRequestKey) {
        self.request = request
        self.key = key
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
    override func isEqual(object: AnyObject?) -> Bool {
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
