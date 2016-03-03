// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageLoading

/** Performs loading of images for the given tasks.
*/
public protocol ImageLoading: class {
    /** Manager that controls image loading.
     */
    weak var manager: ImageLoadingManager? { get set }
    
    /** Resumes loading for the given task.
     */
    func resumeLoadingFor(task: ImageTask)
    
    /** Suspends loading for the given task.
     */
    func suspendLoadingFor(task: ImageTask)
    
    /** Cancels loading for the given task.
     */
    func cancelLoadingFor(task: ImageTask)
    
    /** Compares requests for equivalence with regard to caching output images. This method is used for memory caching, in most cases there is no need for filtering out the dynamic part of the request (is there is any).
     */
    func isCacheEquivalent(lhs: ImageRequest, to rhs: ImageRequest) -> Bool
    
    /** Invalidates the receiver. This method gets called by the manager when it is invalidated.
     */
    func invalidate()
    
    /** Clears the receiver's cache storage (if any).
     */
    func removeAllCachedImages()
}

// MARK: - ImageLoadingDelegate

/** Manages image loading.
*/
public protocol ImageLoadingManager: class {
    /** Sent periodically to notify the manager of the task progress.
     */
    func loader(loader: ImageLoading, task: ImageTask, didUpdateProgress progress: ImageTaskProgress)
    
    /** Sent when loading for the task is completed.
     */
    func loader(loader: ImageLoading, task: ImageTask, didCompleteWithImage image: Image?, error: ErrorType?, userInfo: Any?)
}

// MARK: - ImageLoaderConfiguration

public struct ImageLoaderConfiguration {
    public var dataLoader: ImageDataLoading
    public var decoder: ImageDecoding
    
    /** Maximum number of concurrent executing NSURLSessionTasks. Default value is 10.
     */
    public var maxConcurrentDataTaskCount = 10
    
    /** Image decoding queue. Default queue has a maximum concurrent operation count 1.
     */
    public var decodingQueue = NSOperationQueue(maxConcurrentOperationCount: 1)
    
    /** Image processing queue. Default queue has a maximum concurrent operation count 2.
     */
    public var processingQueue = NSOperationQueue(maxConcurrentOperationCount: 2)
    
    @available(*, deprecated=2.2)
    public var congestionControlEnabled = true
    
    /**
     Initializes configuration with data loader and image decoder.
     
     - parameter dataLoader: Image data loader.
     - parameter decoder: Image decoder. Default `ImageDecoder` instance is created if the parameter is omitted.
     */
    public init(dataLoader: ImageDataLoading, decoder: ImageDecoding = ImageDecoder()) {
        self.dataLoader = dataLoader
        self.decoder = decoder
    }
}

// MARK: - ImageLoaderDelegate

/** Image loader customization endpoints.
*/
public protocol ImageLoaderDelegate {
    /** Compares requests for equivalence with regard to loading image data. Requests should be considered equivalent if the loader can handle both requests with a single session task.
     */
    func loader(loader: ImageLoader, isLoadEquivalent lhs: ImageRequest, to rhs: ImageRequest) -> Bool
    
    /** Compares requests for equivalence with regard to caching output images. This method is used for memory caching, in most cases there is no need for filtering out the dynamic part of the request (is there is any).
     */
    func loader(loader: ImageLoader, isCacheEquivalent lhs: ImageRequest, to rhs: ImageRequest) -> Bool
    
    /** Returns processor for the given request and image.
     */
    func loader(loader: ImageLoader, processorFor: ImageRequest, image: Image) -> ImageProcessing?
}

/** Default implementation of ImageLoaderDelegate.
 */
public extension ImageLoaderDelegate {
    /** Constructs image decompressor based on the request's target size and content mode (if decompression is allowed). Combined the decompressor with the processor provided in the request.
     */
    public func processorFor(request: ImageRequest, image: Image) -> ImageProcessing? {
        var processors = [ImageProcessing]()
        if request.shouldDecompressImage, let decompressor = self.decompressorFor(request) {
            processors.append(decompressor)
        }
        if let processor = request.processor {
            processors.append(processor)
        }
        return processors.isEmpty ? nil : ImageProcessorComposition(processors: processors)
    }
    
    public func decompressorFor(request: ImageRequest) -> ImageProcessing? {
        #if os(OSX)
            return nil
        #else
            return ImageDecompressor(targetSize: request.targetSize, contentMode: request.contentMode)
        #endif
    }
}

/**
 Default implementation of ImageLoaderDelegate.
 
 The default implementation is provided in a class which allows methods to be overridden.
 */
public class ImageLoaderDefaultDelegate: ImageLoaderDelegate {
    public init() {}
    
    /** Compares request `URL`, `cachePolicy`, `timeoutInterval`, `networkServiceType` and `allowsCellularAccess`.
     */
    public func loader(loader: ImageLoader, isLoadEquivalent lhs: ImageRequest, to rhs: ImageRequest) -> Bool {
        let a = lhs.URLRequest, b = rhs.URLRequest
        return a.URL == b.URL &&
            a.cachePolicy == b.cachePolicy &&
            a.timeoutInterval == b.timeoutInterval &&
            a.networkServiceType == b.networkServiceType &&
            a.allowsCellularAccess == b.allowsCellularAccess
    }
    
    /** Compares request `URL`s, decompression parameters (`shouldDecompressImage`, `targetSize` and `contentMode`), and processors.
     */
    public func loader(loader: ImageLoader, isCacheEquivalent lhs: ImageRequest, to rhs: ImageRequest) -> Bool {
        guard lhs.URLRequest.URL == rhs.URLRequest.URL else {
            return false
        }
        return lhs.shouldDecompressImage == rhs.shouldDecompressImage &&
            lhs.targetSize == rhs.targetSize &&
            lhs.contentMode == rhs.contentMode &&
            isEquivalent(lhs.processor, rhs: rhs.processor)
    }
    
    private func isEquivalent(lhs: ImageProcessing?, rhs: ImageProcessing?) -> Bool {
        switch (lhs, rhs) {
        case let (l?, r?): return l.isEquivalent(r)
        case (nil, nil): return true
        default: return false
        }
    }
    
    /** Constructs image decompressor based on the request's target size and content mode (if decompression is allowed). Combined the decompressor with the processor provided in the request.
     */
    public func loader(loader: ImageLoader, processorFor request: ImageRequest, image: Image) -> ImageProcessing? {
        return self.processorFor(request, image: image)
    }
}

// MARK: - ImageLoader

/**
Performs loading of images for the image tasks.

This class uses multiple dependencies provided in its configuration. Image data is loaded using an object conforming to `ImageDataLoading` protocol. Image data is decoded via `ImageDecoding` protocol. Decoded images are processed by objects conforming to `ImageProcessing` protocols.

- Provides transparent loading, decoding and processing with a single completion signal
- Reuses data tasks for equivalent image tasks
*/
public class ImageLoader: ImageLoading {
    public weak var manager: ImageLoadingManager?
    public let configuration: ImageLoaderConfiguration
    
    /** Delegate that the receiver was initialized with. Image loader holds a strong reference to its delegate!
     */
    public let delegate: ImageLoaderDelegate
    
    private var loadStates = [ImageTask : ImageLoadState]()
    private var dataTasks = [ImageRequestKey : ImageDataTask]()
    private let taskQueue = TaskQueue()
    private let queue = dispatch_queue_create("ImageLoader.Queue", DISPATCH_QUEUE_SERIAL)
    
    /**
     Initializes image loader with a configuration and a delegate.
     
     - parameter delegate: Instance of `ImageLoaderDefaultDelegate` created if the parameter is omitted. Image loader holds a strong reference to its delegate!
     */
    public init(configuration: ImageLoaderConfiguration, delegate: ImageLoaderDelegate = ImageLoaderDefaultDelegate()) {
        self.configuration = configuration
        self.delegate = delegate
        self.taskQueue.maxExecutingTaskCount = configuration.maxConcurrentDataTaskCount
    }
    
    public func resumeLoadingFor(task: ImageTask) {
        // Image loader performs all tasks asynchronously on its serial queue.
        dispatch_async(self.queue) {
            self._resumeLoadingFor(task)
        }
    }
    
    private func _resumeLoadingFor(task: ImageTask) {
        // ImageDataTasks wraps NSURLSessionTask
        // ImageLoader reuses ImageDataTasks for equivalent requests
        let key = ImageRequestKey(task.request, owner: self)
        var dataTask: ImageDataTask! = self.dataTasks[key]
        if dataTask == nil {
            dataTask = self.dataTaskWith(task.request, key: key)
            self.dataTasks[key] = dataTask
        } else {
            // Subscribing to the existing task, let the manager know about its progress
            self.manager?.loader(self, task: task, didUpdateProgress: dataTask.progress)
        }
        self.loadStates[task] = ImageLoadState.Loading(dataTask)
        dataTask.resume(task)
    }
    
    private func dataTaskWith(request: ImageRequest, key: ImageRequestKey) -> ImageDataTask {
        let dataTask = ImageDataTask(key: key, queue: self.taskQueue)
        dataTask.URLSessionTask = self.configuration.dataLoader.taskWith(request, progress: { [weak self] completed, total in
            self?.dataTask(dataTask, didUpdateProgress: ImageTaskProgress(completed: completed, total: total))
            }, completion: { [weak self] data, response, error in
                self?.dataTask(dataTask, didCompleteWithData: data, response: response, error: error)
            })
        #if !os(OSX)
            if let priority = request.priority {
                dataTask.URLSessionTask?.priority = priority
            }
        #endif
        return dataTask
    }
    
    private func dataTask(dataTask: ImageDataTask, didUpdateProgress progress: ImageTaskProgress) {
        dispatch_async(self.queue) {
            dataTask.progress = progress
            for task in dataTask.tasks {
                self.manager?.loader(self, task: task, didUpdateProgress: dataTask.progress)
            }
        }
    }
    
    private func dataTask(dataTask: ImageDataTask, didCompleteWithData data: NSData?, response: NSURLResponse?, error: ErrorType?) {
        dispatch_async(self.queue) {
            // Mark task as finished when NSURLSessionTask is actually completed/cancelled by NSURLSession
            self.taskQueue.finish(dataTask.URLSessionTask)
        }
        guard error == nil, let data = data else {
            self.dataTask(dataTask, didCompleteWithImage: nil, error: error)
            return;
        }
        self.configuration.decodingQueue.addOperationWithBlock { [weak self] in
            let image = self?.configuration.decoder.decode(data, response: response)
            self?.dataTask(dataTask, didCompleteWithImage: image, error: (image == nil ? errorWithCode(.DecodingFailed) : nil))
        }
    }
    
    private func dataTask(dataTask: ImageDataTask, didCompleteWithImage image: Image?, error: ErrorType?) {
        dispatch_async(self.queue) {
            for task in dataTask.tasks {
                if let image = image, processor = self.delegate.loader(self, processorFor:task.request, image: image) {
                    let operation = NSBlockOperation { [weak self] in
                        let image = processor.process(image)
                        self?.complete(task, image: image, error: (image == nil ? errorWithCode(.ProcessingFailed) : nil))
                    }
                    self.configuration.processingQueue.addOperation(operation)
                    self.loadStates[task] = ImageLoadState.Processing(operation)
                } else {
                    self.complete(task, image: image, error: error)
                }
            }
            dataTask.complete()
            self.remove(dataTask)
        }
    }
    
    private func complete(task: ImageTask, image: Image?, error: ErrorType?) {
        dispatch_async(self.queue) {
            self.manager?.loader(self, task: task, didCompleteWithImage: image, error: error, userInfo: nil)
            self.loadStates[task] = nil
        }
    }
    
    public func suspendLoadingFor(task: ImageTask) {
        dispatch_async(self.queue) {
            self._suspendLoadingFor(task)
        }
    }
    
    /** Underlying data task is suspended when there are no executing tasks registered with it.
     */
    private func _suspendLoadingFor(task: ImageTask) {
        if let state = self.loadStates[task] {
            switch state {
            case .Loading(let sessionTask):
                sessionTask.suspend(task)
            default: break
            }
        }
    }
    
    public func cancelLoadingFor(task: ImageTask) {
        dispatch_async(self.queue) {
            self._cancelLoadingFor(task)
        }
    }
    
    private func _cancelLoadingFor(task: ImageTask) {
        if let state = self.loadStates[task] {
            switch state {
            case .Loading(let sessionTask):
                // Underlying data task is cancelled when there are no outstanding tasks (executing or suspended) registered with it.
                if sessionTask.cancel(task) {
                    self.remove(sessionTask)
                }
            case .Processing(let operation):
                operation.cancel()
            }
            self.loadStates[task] = nil
        }
    }
    
    private func remove(task: ImageDataTask) {
        // We might receive signal from the task which place was taken by another task
        if self.dataTasks[task.key] === task {
            self.dataTasks[task.key] = nil
        }
    }
    
    public func isCacheEquivalent(lhs: ImageRequest, to rhs: ImageRequest) -> Bool {
        return self.delegate.loader(self, isCacheEquivalent: lhs, to: rhs)
    }
    
    public func invalidate() {
        self.configuration.dataLoader.invalidate()
    }
    
    public func removeAllCachedImages() {
        self.configuration.dataLoader.removeAllCachedImages()
    }
}

// MARK: ImageLoader: ImageRequestKeyOwner

extension ImageLoader: ImageRequestKeyOwner {
    public func isEqual(lhs: ImageRequestKey, to rhs: ImageRequestKey) -> Bool {
        return self.delegate.loader(self, isLoadEquivalent: lhs.request, to: rhs.request)
    }
}

// MARK: - ImageLoadState

private enum ImageLoadState {
    case Loading(ImageDataTask)
    case Processing(NSOperation)
}

// MARK: - ImageDataTask

private class ImageDataTask {
    let key: ImageRequestKey
    var URLSessionTask: NSURLSessionTask!
    var executingTasks = Set<ImageTask>()
    var suspendedTasks = Set<ImageTask>()
    var tasks: Set<ImageTask> {
        return self.executingTasks.union(self.suspendedTasks)
    }
    var progress: ImageTaskProgress = ImageTaskProgress()
    let queue: TaskQueue
    
    init(key: ImageRequestKey, queue: TaskQueue) {
        self.key = key
        self.queue = queue
    }
    
    func resume(task: ImageTask) {
        self.suspendedTasks.remove(task)
        self.executingTasks.insert(task)
        self.queue.resume(self.URLSessionTask)
    }
    
    func cancel(task: ImageTask) -> Bool {
        self.executingTasks.remove(task)
        self.suspendedTasks.remove(task)
        if self.tasks.isEmpty {
            self.queue.cancel(self.URLSessionTask)
            return true
        }
        return false
    }
    
    func suspend(task: ImageTask) {
        self.executingTasks.remove(task)
        self.suspendedTasks.insert(task)
        if self.executingTasks.isEmpty {
            self.queue.suspend(self.URLSessionTask)
        }
    }
    
    func complete() {
        self.executingTasks.removeAll()
        self.suspendedTasks.removeAll()
    }
}

// MARK: TaskQueue

private class TaskQueue {
    var pendingTasks = NSMutableOrderedSet()
    var executingTasks = Set<NSURLSessionTask>()
    var maxExecutingTaskCount = 1
    
    func resume(task: NSURLSessionTask) {
        if !self.pendingTasks.containsObject(task) && !self.executingTasks.contains(task) {
            self.pendingTasks.addObject(task)
            self.setNeedsExecute()
        }
    }
    
    func suspend(task: NSURLSessionTask) {
        if self.pendingTasks.containsObject(task) {
            self.pendingTasks.removeObject(task)
        } else if self.executingTasks.contains(task) {
            self.executingTasks.remove(task)
            task.suspend()
            self.setNeedsExecute()
        }
    }
    
    func cancel(task: NSURLSessionTask) {
        if self.pendingTasks.containsObject(task) {
            self.pendingTasks.removeObject(task)
        } else if self.executingTasks.contains(task) {
            task.cancel()
        }
    }
    
    func finish(task: NSURLSessionTask) {
        if self.pendingTasks.containsObject(task) {
            self.pendingTasks.removeObject(task)
        } else if self.executingTasks.contains(task) {
            self.executingTasks.remove(task)
            self.setNeedsExecute()
        }
    }
    
    func setNeedsExecute() {
        self.execute()
    }
    
    func execute() {
        while self.pendingTasks.count > 0 && self.executingTasks.count < self.maxExecutingTaskCount {
            let task = self.pendingTasks.lastObject! as! NSURLSessionTask
            self.pendingTasks.removeObjectAtIndex(self.pendingTasks.count - 1)
            self.executingTasks.insert(task)
            task.resume()
            print("execute \(task), pending: \(self.pendingTasks.count), executing: \(self.executingTasks.count)")
        }
    }
}
