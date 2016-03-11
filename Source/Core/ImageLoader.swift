// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageLoading

/// Performs loading of images.
public protocol ImageLoading: class {
    /// Manager that controls image loading.
    weak var manager: ImageLoadingManager? { get set }
    
    /// Resumes loading for the given task.
    func resumeLoadingFor(task: ImageTask)

    /// Cancels loading for the given task.
    func cancelLoadingFor(task: ImageTask)
    
    /// Compares requests for equivalence with regard to caching output images. This method is used for memory caching, in most cases there is no need for filtering out the dynamic part of the request (is there is any).
    func isCacheEquivalent(lhs: ImageRequest, to rhs: ImageRequest) -> Bool
    
    /// Invalidates the receiver. This method gets called by the manager when it is invalidated.
    func invalidate()
    
    /// Clears the receiver's cache storage (if any).
    func removeAllCachedImages()
}

// MARK: - ImageLoadingDelegate

/// Manages image loading.
public protocol ImageLoadingManager: class {
    /// Sent periodically to notify the manager of the task progress.
    func loader(loader: ImageLoading, task: ImageTask, didUpdateProgress progress: ImageTaskProgress)
    
    /// Sent when loading for the task is completed.
    func loader(loader: ImageLoading, task: ImageTask, didCompleteWithImage image: Image?, error: ErrorType?, userInfo: Any?)
}

// MARK: - ImageLoaderConfiguration

/// Configuration options for an ImageLoader.
public struct ImageLoaderConfiguration {
    /// Performs loading of image data.
    public var dataLoader: ImageDataLoading

    /// Decodes data into image objects.
    public var decoder: ImageDecoding
    
    /// Maximum number of concurrent executing NSURLSessionTasks. Default value is 10.
    public var maxConcurrentSessionTaskCount = 10
    
    /// Image decoding queue. Default queue has a maximum concurrent operation count 1.
    public var decodingQueue = NSOperationQueue(maxConcurrentOperationCount: 1)
    
    /// Image processing queue. Default queue has a maximum concurrent operation count 2.
    public var processingQueue = NSOperationQueue(maxConcurrentOperationCount: 2)

    /// Determines whether the image loader should reuse NSURLSessionTasks for equivalent image requests. Default value is true.
    public var taskReusingEnabled = true

    /// Prevents trashing of NSURLSession by delaying requests. Default value is true.
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

/// Image loader customization endpoints.
public protocol ImageLoaderDelegate {
    /// Compares requests for equivalence with regard to loading image data. Requests should be considered equivalent if the loader can handle both requests with a single session task.
    func loader(loader: ImageLoader, isLoadEquivalent lhs: ImageRequest, to rhs: ImageRequest) -> Bool
    
    /// Compares requests for equivalence with regard to caching output images. This method is used for memory caching, in most cases there is no need for filtering out the dynamic part of the request (is there is any).
    func loader(loader: ImageLoader, isCacheEquivalent lhs: ImageRequest, to rhs: ImageRequest) -> Bool
    
    /// Returns processor for the given request and image.
    func loader(loader: ImageLoader, processorFor: ImageRequest, image: Image) -> ImageProcessing?
}

/// Default implementation of ImageLoaderDelegate.
public extension ImageLoaderDelegate {
    /// Constructs image decompressor based on the request's target size and content mode (if decompression is allowed). Combined the decompressor with the processor provided in the request.
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

    /// Returns decompressor for the given request.
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
    /// Initializes the delegate.
    public init() {}
    
    /// Compares request `URL`, `cachePolicy`, `timeoutInterval`, `networkServiceType` and `allowsCellularAccess`.
    public func loader(loader: ImageLoader, isLoadEquivalent lhs: ImageRequest, to rhs: ImageRequest) -> Bool {
        let a = lhs.URLRequest, b = rhs.URLRequest
        return a.URL == b.URL &&
            a.cachePolicy == b.cachePolicy &&
            a.timeoutInterval == b.timeoutInterval &&
            a.networkServiceType == b.networkServiceType &&
            a.allowsCellularAccess == b.allowsCellularAccess
    }
    
    /// Compares request `URL`s, decompression parameters (`shouldDecompressImage`, `targetSize` and `contentMode`), and processors.
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
    
    /// Constructs image decompressor based on the request's target size and content mode (if decompression is allowed). Combined the decompressor with the processor provided in the request.
    public func loader(loader: ImageLoader, processorFor request: ImageRequest, image: Image) -> ImageProcessing? {
        return self.processorFor(request, image: image)
    }
}

// MARK: - ImageLoader

/**
Performs loading of images for the image tasks.

This class uses multiple dependencies provided in its configuration. Image data is loaded using an object conforming to `ImageDataLoading` protocol. Image data is decoded via `ImageDecoding` protocol. Decoded images are processed by objects conforming to `ImageProcessing` protocols.

- Provides transparent loading, decoding and processing with a single completion signal
- Reuses session tasks for equivalent request
*/
public class ImageLoader: ImageLoading {
    /// Manages image loading.
    public weak var manager: ImageLoadingManager?

    /// The configuration that the receiver was initialized with.
    public let configuration: ImageLoaderConfiguration
    
    /// Delegate that the receiver was initialized with. Image loader holds a strong reference to its delegate!
    public let delegate: ImageLoaderDelegate
    
    private var loadStates = [ImageTask : ImageLoadState]()
    private var dataTasks = [ImageRequestKey : DataTask]()
    private let taskQueue: TaskQueue
    private let queue = dispatch_queue_create("ImageLoader.Queue", DISPATCH_QUEUE_SERIAL)
    
    /**
     Initializes image loader with a configuration and a delegate.

     - parameter delegate: Instance of `ImageLoaderDefaultDelegate` created if the parameter is omitted. Image loader holds a strong reference to its delegate!
     */
    public init(configuration: ImageLoaderConfiguration, delegate: ImageLoaderDelegate = ImageLoaderDefaultDelegate()) {
        self.configuration = configuration
        self.delegate = delegate
        self.taskQueue = TaskQueue(queue: queue)
        self.taskQueue.maxExecutingTaskCount = configuration.maxConcurrentSessionTaskCount
        self.taskQueue.congestionControlEnabled = configuration.congestionControlEnabled
    }

    /// Resumes loading for the image task.
    public func resumeLoadingFor(task: ImageTask) {
        // Image loader performs all tasks asynchronously on its serial queue.
        dispatch_async(queue) {
            // DataTask wraps NSURLSessionTask
            // ImageLoader reuses DataTasks for equivalent requests
            let key = ImageRequestKey(task.request, owner: self)
            var dataTask: DataTask! = self.configuration.taskReusingEnabled ? self.dataTasks[key] : nil
            if dataTask == nil {
                dataTask = self.dataTaskWith(task.request, key: key)
                if self.configuration.taskReusingEnabled {
                    self.dataTasks[key] = dataTask
                }
            } else {
                // Subscribing to the existing task, let the manager know about its progress
                self.manager?.loader(self, task: task, didUpdateProgress: dataTask.progress)
            }
            self.loadStates[task] = ImageLoadState.Loading(dataTask)

            dataTask.imageTasks.insert(task)
            self.taskQueue.resume(dataTask.URLSessionTask)
        }
    }

    private func dataTaskWith(request: ImageRequest, key: ImageRequestKey) -> DataTask {
        let dataTask = DataTask(key: key)
        dataTask.URLSessionTask = configuration.dataLoader.taskWith(request, progress: { [weak self] completed, total in
                self?.dataTask(dataTask, didUpdateProgress: ImageTaskProgress(completed: completed, total: total))
            }, completion: { [weak self] data, response, error in
                self?.dataTask(dataTask, didCompleteWithData: data, response: response, error: error)
            })
        #if !os(OSX)
            if let priority = request.priority {
                dataTask.URLSessionTask.priority = priority
            }
        #endif
        return dataTask
    }
    
    private func dataTask(dataTask: DataTask, didUpdateProgress progress: ImageTaskProgress) {
        dispatch_async(queue) {
            dataTask.progress = progress
            dataTask.imageTasks.forEach {
                self.manager?.loader(self, task: $0, didUpdateProgress: dataTask.progress)
            }
        }
    }
    
    private func dataTask(dataTask: DataTask, didCompleteWithData data: NSData?, response: NSURLResponse?, error: ErrorType?) {
        dispatch_async(queue) {
            // Mark task as finished when NSURLSessionTask is actually completed/cancelled by NSURLSession
            self.taskQueue.finish(dataTask.URLSessionTask)
        }
        guard error == nil, let data = data else {
            self.dataTask(dataTask, didCompleteWithImage: nil, error: error)
            return;
        }
        configuration.decodingQueue.addOperationWithBlock { [weak self] in
            let image = self?.configuration.decoder.decode(data, response: response)
            self?.dataTask(dataTask, didCompleteWithImage: image, error: (image == nil ? errorWithCode(.DecodingFailed) : nil))
        }
    }
    
    private func dataTask(dataTask: DataTask, didCompleteWithImage image: Image?, error: ErrorType?) {
        dispatch_async(queue) {
            for task in dataTask.imageTasks {
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
            dataTask.imageTasks.removeAll()
            self.remove(dataTask)
        }
    }
    
    private func complete(task: ImageTask, image: Image?, error: ErrorType?) {
        dispatch_async(queue) {
            self.manager?.loader(self, task: task, didCompleteWithImage: image, error: error, userInfo: nil)
            self.loadStates[task] = nil
        }
    }

    /// Cancels loading for the task if there are no other outstanding executing tasks registered with the underlying data task.
    public func cancelLoadingFor(task: ImageTask) {
        dispatch_async(queue) {
            if let state = self.loadStates[task] {
                switch state {
                case .Loading(let dataTask):
                    dataTask.imageTasks.remove(task)
                    if dataTask.imageTasks.isEmpty {
                        self.taskQueue.cancel(dataTask.URLSessionTask)
                    }
                case .Processing(let operation):
                    operation.cancel()
                }
                self.loadStates[task] = nil
            }
        }
    }
        
    private func remove(task: DataTask) {
        // We might receive signal from the task which place was taken by another task
        if dataTasks[task.key] === task {
            dataTasks[task.key] = nil
        }
    }

    /// Comapres two requests using ImageLoaderDelegate.
    public func isCacheEquivalent(lhs: ImageRequest, to rhs: ImageRequest) -> Bool {
        return delegate.loader(self, isCacheEquivalent: lhs, to: rhs)
    }

    /// Signals the data loader to invalidate.
    public func invalidate() {
        configuration.dataLoader.invalidate()
    }

    /// Signals data loader to remove all cached images.
    public func removeAllCachedImages() {
        configuration.dataLoader.removeAllCachedImages()
    }
}

extension ImageLoader: ImageRequestKeyOwner {
    /// Compares two requests for equivalence using ImageLoaderDelegate.
    public func isEqual(lhs: ImageRequestKey, to rhs: ImageRequestKey) -> Bool {
        return self.delegate.loader(self, isLoadEquivalent: lhs.request, to: rhs.request)
    }
}

private enum ImageLoadState {
    case Loading(DataTask)
    case Processing(NSOperation)
}

// MARK: - DataTask

private class DataTask {
    let key: ImageRequestKey
    var URLSessionTask: NSURLSessionTask! // nonnull
    var imageTasks = Set<ImageTask>()
    var progress: ImageTaskProgress = ImageTaskProgress()
    
    init(key: ImageRequestKey) {
        self.key = key
    }
}

// MARK: TaskQueue

/// Limits number of concurrent tasks, prevents trashing of NSURLSession
private class TaskQueue {
    var maxExecutingTaskCount = 8
    var congestionControlEnabled = true

    private let queue: dispatch_queue_t
    private var pendingTasks = NSMutableOrderedSet()
    private var executingTasks = Set<NSURLSessionTask>()
    private var executing = false

    init(queue: dispatch_queue_t) {
        self.queue = queue
    }

    func resume(task: NSURLSessionTask) {
        if !pendingTasks.containsObject(task) && !executingTasks.contains(task) {
            pendingTasks.addObject(task)
            setNeedsExecute()
        }
    }

    func cancel(task: NSURLSessionTask) {
        if pendingTasks.containsObject(task) {
            pendingTasks.removeObject(task)
        } else if executingTasks.contains(task) {
            executingTasks.remove(task)
            task.cancel()
            setNeedsExecute()
        }
    }

    func finish(task: NSURLSessionTask) {
        if pendingTasks.containsObject(task) {
            pendingTasks.removeObject(task)
        } else if executingTasks.contains(task) {
            executingTasks.remove(task)
            setNeedsExecute()
        }
    }

    func setNeedsExecute() {
        if !executing {
            executing = true
            if congestionControlEnabled {
                // Executing tasks too frequently might trash NSURLSession to the point it would crash or stop executing tasks
                let delay = min(30.0, 8.0 + Double(executingTasks.count))
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(delay * Double(NSEC_PER_MSEC))), queue) {
                    self.execute()
                }
            } else {
                execute()
            }
        }
    }

    func execute() {
        executing = false
        if let task = pendingTasks.firstObject as? NSURLSessionTask where executingTasks.count < maxExecutingTaskCount {
            pendingTasks.removeObjectAtIndex(0)
            executingTasks.insert(task)
            task.resume()
            setNeedsExecute()
        }
    }
}
