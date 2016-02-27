// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/** The domain used for creating all ImageManager errors.

The image manager would produce either errors in ImageManagerErrorDomain or errors in NSURLErrorDomain (which are not wrapped).
 */
public let ImageManagerErrorDomain = "Nuke.ImageManagerErrorDomain"

/** The image manager error codes.
 */
public enum ImageManagerErrorCode: Int {
    /** Returned when the image manager encountered an error that it cannot interpret.
     */
    case Unknown = -15001

    /** Returned when the image task gets cancelled.
     */
    case Cancelled = -15002
    
    /** Returned when the image manager fails decode image data.
     */
    case DecodingFailed = -15003
    
    /** Returned when the image manager fails to process image data.
     */
    case ProcessingFailed = -15004
}

// MARK: - ImageManagerConfiguration

public struct ImageManagerConfiguration {
    public var loader: ImageLoading
    public var cache: ImageMemoryCaching?
    
    /** Default value is 2.
     */
    public var maxConcurrentPreheatingTaskCount = 2
    
    /**
     Initializes configuration with an image loader and memory cache.
     
     - parameter loader: Image loader.
     - parameter cache: Memory cache. Default `ImageMemoryCache` instance is created if the parameter is omitted.
     */
    public init(loader: ImageLoading, cache: ImageMemoryCaching? = ImageMemoryCache()) {
        self.loader = loader
        self.cache = cache
    }
    
    /**
     Convenience initializer that creates instance of `ImageLoader` class with a given `dataLoader` and `decoder`, then calls the default initializer.
     
     - parameter dataLoader: Image data loader.
     - parameter decoder: Image decoder. Default `ImageDecoder` instance is created if the parameter is omitted.
     - parameter cache: Memory cache. Default `ImageMemoryCache` instance is created if the parameter is omitted.
     */
    public init(dataLoader: ImageDataLoading, decoder: ImageDecoding = ImageDecoder(), cache: ImageMemoryCaching? = ImageMemoryCache()) {
        let loader = ImageLoader(configuration: ImageLoaderConfiguration(dataLoader: dataLoader, decoder: decoder))
        self.init(loader: loader, cache: cache)
    }
}

// MARK: - ImageManager

/**
The `ImageManager` class and related classes provide methods for loading, processing, caching and preheating images.

`ImageManager` is also a pipeline that loads images using injectable dependencies, which makes it highly customizable. See https://github.com/kean/Nuke#design for more info.
*/
public class ImageManager {
    private var executingTasks = Set<ImageTaskInternal>()
    private var preheatingTasks = [ImageRequestKey: ImageTaskInternal]()
    private let lock = NSRecursiveLock()
    private var invalidated = false
    private var needsToExecutePreheatingTasks = false
    private var taskIdentifier: Int32 = 0
    private var nextTaskIdentifier: Int {
        return Int(OSAtomicIncrement32(&taskIdentifier))
    }
    private var loader: ImageLoading {
        return self.configuration.loader
    }
    private var cache: ImageMemoryCaching? {
        return self.configuration.cache
    }
    
    // MARK: Configuring Manager
    
    public let configuration: ImageManagerConfiguration
    
    public init(configuration: ImageManagerConfiguration) {
        self.configuration = configuration
        self.loader.manager = self
    }
    
    // MARK: Adding Tasks
    
    /**
     Creates a task with a given request. After you create a task, you start it by calling its resume method.
     
     The manager holds a strong reference to the task until it is either completes or get cancelled.
     */
    public func taskWith(request: ImageRequest) -> ImageTask {
        return ImageTaskInternal(manager: self, request: request, identifier: self.nextTaskIdentifier)
    }
    
    // MARK: FSM (ImageTaskState)
    
    private func setState(state: ImageTaskState, forTask task: ImageTaskInternal)  {
        if task.isValidNextState(state) {
            self.transitionStateAction(task.state, toState: state, task: task)
            task.state = state
            self.enterStateAction(state, task: task)
        }
    }
    
    private func transitionStateAction(fromState: ImageTaskState, toState: ImageTaskState, task: ImageTaskInternal) {
        if fromState == .Running && toState == .Suspended {
            self.loader.suspendLoadingFor(task)
        }
    }
    
    private func enterStateAction(state: ImageTaskState, task: ImageTaskInternal) {
        switch state {
        case .Running:
            switch task.request.memoryCachePolicy {
            case .ReturnCachedImageElseLoad:
                if let response = self.responseForRequest(task.request) {
                    // FIXME: Should ImageResponse contain a `fastResponse` property?
                    task.response = ImageResponse.Success(response.image, ImageResponseInfo(fastResponse: true, userInfo: response.userInfo))
                    self.setState(.Completed, forTask: task)
                    return
                }
            default: break
            }
            self.executingTasks.insert(task)
            self.loader.resumeLoadingFor(task)
        case .Cancelled:
            self.loader.cancelLoadingFor(task)
            task.response = ImageResponse.Failure(errorWithCode(.Cancelled))
            fallthrough
        case .Completed:
            self.executingTasks.remove(task)
            self.setNeedsExecutePreheatingTasks()
            
            let completions = task.completions
            dispathOnMainThread {
                assert(task.response != nil)
                completions.forEach { $0(task.response!) }
            }
        default: break
        }
    }
    
    // MARK: Preheating
    
    /**
    Prepares images for the given requests for later use.
    
    When you call this method, ImageManager starts to load and cache images for the given requests. ImageManager caches images with the exact target size, content mode, and filters. At any time afterward, you can create tasks with equivalent requests.
    */
    public func startPreheatingImages(requests: [ImageRequest]) {
        self.perform {
            for request in requests {
                let key = ImageRequestKey(request, owner: self)
                if self.preheatingTasks[key] == nil {
                    self.preheatingTasks[key] = ImageTaskInternal(manager: self, request: request, identifier: self.nextTaskIdentifier).completion { [weak self] _ in
                        self?.preheatingTasks[key] = nil
                    }
                }
            }
            self.setNeedsExecutePreheatingTasks()
        }
    }
    
    /** Stop preheating for the given requests. The request parameters should match the parameters used in startPreheatingImages method.
     */
    public func stopPreheatingImages(requests: [ImageRequest]) {
        self.perform {
            self.cancelTasks(requests.flatMap {
                return self.preheatingTasks[ImageRequestKey($0, owner: self)]
            })
        }
    }
    
    /** Stops all preheating tasks.
     */
    public func stopPreheatingImages() {
        self.perform { self.cancelTasks(self.preheatingTasks.values) }
    }
    
    private func setNeedsExecutePreheatingTasks() {
        if !self.needsToExecutePreheatingTasks && !self.invalidated {
            self.needsToExecutePreheatingTasks = true
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64((0.15 * Double(NSEC_PER_SEC)))), dispatch_get_main_queue()) {
                [weak self] in self?.perform {
                    self?.executePreheatingTasksIfNeeded()
                }
            }
        }
    }
    
    private func executePreheatingTasksIfNeeded() {
        self.needsToExecutePreheatingTasks = false
        var executingTaskCount = self.executingTasks.count
        // FIXME: Use sorted dictionary
        for task in (self.preheatingTasks.values.sort { $0.identifier < $1.identifier }) {
            if executingTaskCount > self.configuration.maxConcurrentPreheatingTaskCount {
                break
            }
            if task.state == .Suspended {
                self.setState(.Running, forTask: task)
                executingTaskCount++
            }
        }
    }
    
    // MARK: Memory Caching
    
    /** Returns response from the memory cache.
    */
    public func responseForRequest(request: ImageRequest) -> ImageCachedResponse? {
        return self.cache?.responseForKey(ImageRequestKey(request, owner: self))
    }
    
    /** Stores response into the memory cache.
     */
    public func setResponse(response: ImageCachedResponse, forRequest request: ImageRequest) {
        self.cache?.setResponse(response, forKey: ImageRequestKey(request, owner: self))
    }
    
    /** Stores response from the memory cache.
     */
    public func removeResponseForRequest(request: ImageRequest) {
        self.cache?.removeResponseForKey(ImageRequestKey(request, owner: self))
    }
    
    // MARK: Managing the Manager
    
    /** Cancels all outstanding tasks and then invalidates the manager. New image tasks may not be resumed.
    */
    public func invalidateAndCancel() {
        self.perform {
            self.loader.manager = nil
            self.cancelTasks(self.executingTasks)
            self.preheatingTasks.removeAll()
            self.loader.invalidate()
            self.invalidated = true
        }
    }
    
    /** Removes all cached images by calling corresponding methods on memory cache and image loader.
     */
    public func removeAllCachedImages() {
        self.cache?.clear()
        self.loader.removeAllCachedImages()
    }
    
    /** Returns all executing tasks and all preheating tasks. Set with executing tasks might contain currently executing preheating tasks.
     */
    public var tasks: (executingTasks: Set<ImageTask>, preheatingTasks: Set<ImageTask>) {
        var executingTasks: Set<ImageTask>!
        var preheatingTasks: Set<ImageTask>!
        self.perform {
            executingTasks = self.executingTasks
            preheatingTasks = Set(self.preheatingTasks.values)
        }
        return (executingTasks, preheatingTasks)
    }


    // MARK: Misc
    
    private func perform(@noescape closure: Void -> Void) {
        self.lock.lock()
        if !self.invalidated { closure() }
        self.lock.unlock()
    }
    
    private func cancelTasks<T: SequenceType where T.Generator.Element == ImageTaskInternal>(tasks: T) {
        tasks.forEach { self.setState(.Cancelled, forTask: $0) }
    }
}


extension ImageManager: ImageLoadingManager {
    
    // MARK: ImageManager: ImageLoadingManager
    
    public func loader(loader: ImageLoading, task: ImageTask, didUpdateProgress progress: ImageTaskProgress) {
        dispatch_async(dispatch_get_main_queue()) {
            task.progress = progress
            task.progressHandler?(progress: progress)
        }
    }
    
    public func loader(loader: ImageLoading, task: ImageTask, didCompleteWithImage image: Image?, error: ErrorType?, userInfo: Any?) {
        let task = task as! ImageTaskInternal
        if let image = image {
            if task.request.memoryCacheStorageAllowed {
                self.setResponse(ImageCachedResponse(image: image, userInfo: userInfo), forRequest: task.request)
            }
            task.response = ImageResponse.Success(image, ImageResponseInfo(fastResponse: false, userInfo: userInfo))
        } else {
            task.response = ImageResponse.Failure(error ?? errorWithCode(.Unknown))
        }
        self.perform { self.setState(.Completed, forTask: task) }
    }
}


extension ImageManager: ImageTaskManaging {
    
    // MARK: ImageManager: ImageTaskManaging
    
    private func resume(task: ImageTaskInternal) {
        self.perform { self.setState(.Running, forTask: task) }
    }
    
    private func suspend(task: ImageTaskInternal) {
        self.perform { self.setState(.Suspended, forTask: task) }
    }
    
    private func cancel(task: ImageTaskInternal) {
        self.perform { self.setState(.Cancelled, forTask: task) }
    }
    
    private func addCompletion(completion: ImageTaskCompletion, forTask task: ImageTaskInternal) {
        self.perform {
            switch task.state {
            case .Completed, .Cancelled:
                dispathOnMainThread {
                    assert(task.response != nil)
                    completion(task.response!.makeFastResponse())
                }
            default:
                task.completions.append(completion)
            }
        }
    }
}


extension ImageManager: ImageRequestKeyOwner {
    
    // MARK: ImageManager: ImageRequestKeyOwner
    
    public func isEqual(lhs: ImageRequestKey, to rhs: ImageRequestKey) -> Bool {
        return self.loader.isCacheEquivalent(lhs.request, to: rhs.request)
    }
}

// MARK: - ImageTaskInternal

private protocol ImageTaskManaging {
    func resume(task: ImageTaskInternal)
    func suspend(task: ImageTaskInternal)
    func cancel(task: ImageTaskInternal)
    func addCompletion(completion: ImageTaskCompletion, forTask task: ImageTaskInternal)
}

private class ImageTaskInternal: ImageTask {
    let manager: ImageTaskManaging
    var completions = [ImageTaskCompletion]()
    
    init(manager: ImageTaskManaging, request: ImageRequest, identifier: Int) {
        self.manager = manager
        super.init(request: request, identifier: identifier)
    }
    
    override func resume() -> Self {
        self.manager.resume(self)
        return self
    }
    
    override func suspend() -> Self {
        self.manager.suspend(self)
        return self
    }
    
    override func cancel() -> Self {
        self.manager.cancel(self)
        return self
    }
    
    override func completion(completion: ImageTaskCompletion) -> Self {
        self.manager.addCompletion(completion, forTask: self)
        return self
    }
    
    // Suspended -> [Running, Cancelled, Completed]
    // Running -> [Suspended, Cancelled, Completed]
    // Cancelled -> []
    // Completed -> []
    func isValidNextState(state: ImageTaskState) -> Bool {
        switch (self.state) {
        case .Suspended, .Running: return true
        default: return false
        }
    }
}
