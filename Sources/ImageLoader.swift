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

    /// Stores image data into a disk cache.
    public var cache: ImageDiskCaching?
    
    /// Maximum number of concurrent executing NSURLSessionTasks. Default value is 10.
    public var maxConcurrentSessionTaskCount = 10

    /// Image caching queue (both read and write). Default queue has a maximum concurrent operation count 2.
    public var cachingQueue = NSOperationQueue(maxConcurrentOperationCount: 2) // based on benchmark: there is a ~2.3x increase in performance when increasing maxConcurrentOperationCount from 1 to 2, but this factor drops sharply right after that
    
    /// Image decoding queue. Default queue has a maximum concurrent operation count 1.
    public var decodingQueue = NSOperationQueue(maxConcurrentOperationCount: 1) // there is no reason to increase maxConcurrentOperationCount, because the built-in ImageDecoder locks while decoding data.
    
    /// Image processing queue. Default queue has a maximum concurrent operation count 2.
    public var processingQueue = NSOperationQueue(maxConcurrentOperationCount: 2)

    /// Prevents trashing of NSURLSession by delaying requests. Default value is true.
    public var congestionControlEnabled = true
    
    /**
     Initializes configuration with data loader and image decoder.
     
     - parameter dataLoader: Image data loader.
     - parameter decoder: Image decoder. Default `ImageDecoder` instance is created if the parameter is omitted.
     */
    public init(dataLoader: ImageDataLoading, decoder: ImageDecoding = ImageDecoder(), cache: ImageDiskCaching? = nil) {
        self.dataLoader = dataLoader
        self.decoder = decoder
        self.cache = cache
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
        if request.shouldDecompressImage, let decompressor = decompressorFor(request) {
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
        return lhs.URLRequest.URL == rhs.URLRequest.URL &&
            lhs.shouldDecompressImage == rhs.shouldDecompressImage &&
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
        return processorFor(request, image: image)
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
    private var conf: ImageLoaderConfiguration { return configuration }
    
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
        queue.async {
            if let cache = self.conf.cache {
                // FIXME: Use better approach for managing tasks
                self.loadStates[task] = .CacheLookup(self.conf.cachingQueue.addBlock { [weak self] in
                    let data = cache.dataFor(task)
                    self?.queue.async {
                        if let data = data {
                            self?.decodeData(data, tasks: [task])
                        } else {
                            guard self?.loadStates[task] != nil else { /* no longer registered */ return }
                            self?.loadDataFor(task)
                        }
                    }
                })
            } else {
                self.loadDataFor(task)
            }
        }
    }

    private func loadDataFor(task: ImageTask) {
        // Reuse DataTasks (which wrap NSURLSessionTasks) for equivalent requests
        let key = ImageRequestKey(task.request, owner: self)
        var dataTask: DataTask! = dataTasks[key]
        if dataTask == nil {
            dataTask = createDataTask(request: task.request, key: key)
            dataTasks[key] = dataTask
        } else {
            queue.async { // Subsribed to the existing DataTask, signal its progress
                self.manager?.loader(self, task: task, didUpdateProgress: dataTask.progress)
            }
        }
        dataTask.registeredTasks.insert(task)
        loadStates[task] = .Loading(dataTask)
        taskQueue.resume(dataTask.URLSessionTask)
    }
    
    private func createDataTask(request request: ImageRequest, key: ImageRequestKey) -> DataTask {
        let dataTask = DataTask(key: key)
        dataTask.URLSessionTask = conf.dataLoader.taskWith(request, progress: { [weak self] completed, total in
            self?.queue.async {
                self?.dataTask(dataTask, didUpdateProgress: ImageTaskProgress(completed: completed, total: total))
            }
        }, completion: { [weak self] data, response, error in
            self?.queue.async {
                self?.dataTask(dataTask, didCompleteWithData: data, response: response, error: error)
            }
        })
        #if !os(OSX)
            if let priority = request.priority {
                dataTask.URLSessionTask.priority = priority
            }
        #endif
        return dataTask
    }
    
    private func dataTask(dataTask: DataTask, didUpdateProgress progress: ImageTaskProgress) {
        dataTask.progress = progress
        dataTask.registeredTasks.forEach {
            manager?.loader(self, task: $0, didUpdateProgress: dataTask.progress)
        }
    }
    
    private func dataTask(dataTask: DataTask, didCompleteWithData data: NSData?, response: NSURLResponse?, error: ErrorType?) {
        // Mark task as finished (or cancelled) only when NSURLSession reports it
        taskQueue.finish(dataTask.URLSessionTask)
        
        removeDataTask(dataTask) // No more ImageTasks can register

        if let data = data where error == nil {
            if let response = response, cache = conf.cache {
                conf.cachingQueue.addBlock {
                    // FIXME: The fact that we use first image task is confusing, because there is no direct relation between DataTask reusing and on-disk caching (it's up to the user).
                    if let task = dataTask.registeredTasks.first {
                        cache.setData(data, response: response, forTask: task)
                    }
                }
            }
            
            decodeData(data, response: response, tasks: dataTask.registeredTasks)
        } else {
            dataTask.registeredTasks.forEach {
                complete($0, image: nil, error: error)
            }
        }
    }

    private func decodeData(data: NSData, response: NSURLResponse? = nil, tasks: Set<ImageTask>) {
        let tasks = tasks.filter { loadStates[$0] != nil } // still registered
        guard tasks.count > 0 else { return }
        conf.decodingQueue.addBlock { [weak self] in
            let image = self?.conf.decoder.decode(data, response: response)
            self?.queue.async {
                tasks.forEach {
                    self?.didDecodeImage(image, error: (image == nil ? errorWithCode(.DecodingFailed) : nil), task: $0)
                }
            }
        }
        tasks.forEach { loadStates[$0] = .Decoding() }
    }
    
    private func didDecodeImage(image: Image?, error: ErrorType?, task: ImageTask) {
        if let image = image, processor = delegate.loader(self, processorFor:task.request, image: image) {
            processImage(image, processor: processor, task: task)
        } else {
            complete(task, image: image, error: error)
        }
    }
    
    private func processImage(image: Image, processor: ImageProcessing, task: ImageTask) {
        guard loadStates[task] != nil else { /* no longer registered */ return }
        loadStates[task] = .Processing(conf.processingQueue.addBlock { [weak self] in
            let image = processor.process(image)
            self?.queue.async {
                self?.complete(task, image: image, error: (image == nil ? errorWithCode(.ProcessingFailed) : nil))
            }
        })
    }
    
    private func complete(task: ImageTask, image: Image?, error: ErrorType?) {
        manager?.loader(self, task: task, didCompleteWithImage: image, error: error, userInfo: nil)
        loadStates[task] = nil
    }

    /// Cancels loading for the task if there are no other outstanding executing tasks registered with the underlying data task.
    public func cancelLoadingFor(task: ImageTask) {
        queue.async {
            if let state = self.loadStates[task] {
                switch state {
                case .CacheLookup(let operation): operation.cancel()
                case .Loading(let dataTask):
                    dataTask.registeredTasks.remove(task)
                    if dataTask.registeredTasks.isEmpty {
                        self.taskQueue.cancel(dataTask.URLSessionTask)
                        self.removeDataTask(dataTask) // No more ImageTasks can register
                    }
                case .Decoding: return
                case .Processing(let operation): operation.cancel()
                }
                self.loadStates[task] = nil // No longer registered
            }
        }
    }
        
    private func removeDataTask(task: DataTask) {
        // We might receive signal from the task which place was taken by another task
        if dataTasks[task.key] === task {
            dataTasks[task.key] = nil
        }
    }

    /// Comapres two requests using ImageLoaderDelegate for equivalence in regards to memory caching.
    public func isCacheEquivalent(lhs: ImageRequest, to rhs: ImageRequest) -> Bool {
        return delegate.loader(self, isCacheEquivalent: lhs, to: rhs)
    }

    /// Signals the data loader to invalidate.
    public func invalidate() {
        conf.dataLoader.invalidate()
    }

    /// Signals data loader and cache (if not nil) to remove all cached images.
    public func removeAllCachedImages() {
        conf.cache?.removeAllCachedImages()
        conf.dataLoader.removeAllCachedImages()
    }
}

extension ImageLoader: ImageRequestKeyOwner {
    /// Compares two requests for equivalence using ImageLoaderDelegate.
    public func isEqual(lhs: ImageRequestKey, to rhs: ImageRequestKey) -> Bool {
        return delegate.loader(self, isLoadEquivalent: lhs.request, to: rhs.request)
    }
}

private enum ImageLoadState {
    case CacheLookup(NSOperation)
    case Loading(DataTask)
    case Decoding()
    case Processing(NSOperation)
}

private class DataTask {
    let key: ImageRequestKey
    var URLSessionTask: NSURLSessionTask! // nonnull
    var registeredTasks = Set<ImageTask>()
    var progress: ImageTaskProgress = ImageTaskProgress()
    
    init(key: ImageRequestKey) {
        self.key = key
    }
}
