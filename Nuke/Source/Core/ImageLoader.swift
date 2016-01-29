// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageLoading

/** Performs loading of images for the image tasks.
*/
public protocol ImageLoading: class {
    /** Managers that controls image loading.
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

    /** Compares requests for equivalence with regard to caching output image. This method is used for memory caching, in most cases there is no need for filtering out the dynamic part of the request (is there is any).
     */
    func isCacheEquivalent(lhs: ImageRequest, to rhs: ImageRequest) -> Bool

    /** Invalidates the receiver.
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
    /** Sent periodically to notify delegate of task progress.
     */
    func loader(loader: ImageLoading, task: ImageTask, didUpdateProgress progress: ImageTaskProgress)
    
    /** Send when loading for task is completed.
     */
    func loader(loader: ImageLoading, task: ImageTask, didCompleteWithImage image: Image?, error: ErrorType?, userInfo: Any?)
}

// MARK: - ImageLoaderConfiguration

public struct ImageLoaderConfiguration {
    public var dataLoader: ImageDataLoading
    public var decoder: ImageDecoding

    /** Image decoding queue. See `ImageDecoding` protocol for more info.
     */
    public var decodingQueue = NSOperationQueue(maxConcurrentOperationCount: 1)

    /** Image processing queue. See `ImageProcessing` protocol for more info.
     */
    public var processingQueue = NSOperationQueue(maxConcurrentOperationCount: 2)

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
    /** Compares requests for equivalence with regard to loading image data. Requests should be considered equivalent if data loader can handle both requests with a single session task.
     */
    func loader(loader: ImageLoader, isLoadEquivalent lhs: ImageRequest, to rhs: ImageRequest) -> Bool

    /** Compares requests for equivalence with regard to caching output image. This method is used for memory caching, in most cases there is no need for filtering out the dynamic part of the request (is there is any).
     */
    func loader(loader: ImageLoader, isCacheEquivalent lhs: ImageRequest, to rhs: ImageRequest) -> Bool

    /** Returns processor for the given request and image.
     *     */
    func loader(loader: ImageLoader, processorForRequest: ImageRequest, image: Image) -> ImageProcessing?
}

public extension ImageLoaderDelegate {
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

    /** Compares request `URLs` and processors.
     */
    func loader(loader: ImageLoader, isCacheEquivalent lhs: ImageRequest, to rhs: ImageRequest) -> Bool {
        guard lhs.URLRequest.URL == rhs.URLRequest.URL else {
            return false
        }
        return lhs.shouldDecompressImage == rhs.shouldDecompressImage &&
            lhs.targetSize == rhs.targetSize &&
            lhs.contentMode == rhs.contentMode &&
            isEquivalent(lhs.processor, rhs: rhs.processor)
    }

    /** Returns processor with combined image decompressor constructed based on request's target size and content mode, and image processor provided in image request.
     */
    public func loader(loader: ImageLoader, processorForRequest request: ImageRequest, image: Image) -> ImageProcessing? {
        var processors = [ImageProcessing]()
        if request.shouldDecompressImage, let decompressor = self.decompressorFor(request) {
            processors.append(decompressor)
        }
        if let processor = request.processor {
            processors.append(processor)
        }
        return processors.isEmpty ? nil : ImageProcessorComposition(processors: processors)
    }

    private func decompressorFor(request: ImageRequest) -> ImageProcessing? {
        #if os(OSX)
            return nil
        #else
            return ImageDecompressor(targetSize: request.targetSize, contentMode: request.contentMode)
        #endif
    }

    private func isEquivalent(lhs: ImageProcessing?, rhs: ImageProcessing?) -> Bool {
        switch (lhs, rhs) {
        case let (l?, r?): return l.isEquivalent(r)
        case (nil, nil): return true
        default: return false
        }
    }
}

public class ImageLoaderDefaultDelegate: ImageLoaderDelegate {
    public init() {}
}

// MARK: - ImageLoader

/**
Performs the actual loading of images for the image tasks using objects conforming to `ImageDataLoading`, `ImageDecoding` and `ImageProcessing` protocols. Works in conjunction with the `ImageManager`.

- Provides a transparent loading, decoding and processing with a single completion signal
- Reuses data tasks for multiple equivalent image tasks
- Offloads work to the background queue
*/
public class ImageLoader: ImageLoading {
    public weak var manager: ImageLoadingManager?
    public let configuration: ImageLoaderConfiguration
    public let delegate: ImageLoaderDelegate

    private var dataLoader: ImageDataLoading {
        return self.configuration.dataLoader
    }
    private var executingTasks = [ImageTask : ImageLoadState]()
    private var sessionTasks = [ImageRequestKey : ImageSessionTask]()
    private let queue = dispatch_queue_create("ImageLoader.SerialQueue", DISPATCH_QUEUE_SERIAL)

    /**
     Initializes image loader with a configuration and a delegate.

     - parameter delegate: Instance of `ImageLoaderDefaultDelegate` created if the parameter is omitted.
     */
    public init(configuration: ImageLoaderConfiguration, delegate: ImageLoaderDelegate = ImageLoaderDefaultDelegate()) {
        self.configuration = configuration
        self.delegate = delegate
    }

    public func resumeLoadingFor(task: ImageTask) {
        dispatch_async(self.queue) {
            let key = ImageRequestKey(task.request, owner: self)
            var sessionTask: ImageSessionTask! = self.sessionTasks[key]
            if sessionTask == nil {
                sessionTask = self.sessionTaskWith(task.request, key: key)
                self.sessionTasks[key] = sessionTask
            } else {
                self.manager?.loader(self, task: task, didUpdateProgress: sessionTask.progress)
            }
            self.executingTasks[task] = ImageLoadState.Loading(sessionTask)
            sessionTask.resume(task)
        }
    }

    private func sessionTaskWith(request: ImageRequest, key: ImageRequestKey) -> ImageSessionTask {
        let sessionTask = ImageSessionTask(key: key)
        let dataTask = self.dataLoader.taskWith(request, progress: { [weak self] completed, total in
            self?.sessionTask(sessionTask, didUpdateProgressWithCompletedUnitCount: completed, totalUnitCount: total)
            }, completion: { [weak self] data, response, error in
                self?.sessionTask(sessionTask, didCompleteWithData: data, response: response, error: error)
            })
        sessionTask.dataTask = dataTask
        return sessionTask
    }

    private func sessionTask(sessionTask: ImageSessionTask, didUpdateProgressWithCompletedUnitCount completedUnitCount: Int64, totalUnitCount: Int64) {
        dispatch_async(self.queue) {
            sessionTask.progress = ImageTaskProgress(completed: completedUnitCount, total: totalUnitCount)
            for imageTask in sessionTask.tasks {
                self.manager?.loader(self, task: imageTask, didUpdateProgress: sessionTask.progress)
            }
        }
    }

    private func sessionTask(sessionTask: ImageSessionTask, didCompleteWithData data: NSData?, response: NSURLResponse?, error: ErrorType?) {
        guard let data = data where error == nil else {
            self.sessionTask(sessionTask, didCompleteWithImage: nil, error: error)
            return;
        }
        self.configuration.decodingQueue.addOperationWithBlock { [weak self] in
            let image = self?.configuration.decoder.decode(data)
            self?.sessionTask(sessionTask, didCompleteWithImage: image, error: error)
        }
    }

    private func sessionTask(sessionTask: ImageSessionTask, didCompleteWithImage image: Image?, error: ErrorType?) {
        dispatch_async(self.queue) {
            for imageTask in sessionTask.tasks {
                self.process(image, error: error, forImageTask: imageTask)
            }
            sessionTask.complete()
            self.removeSessionTask(sessionTask)
        }
    }

    private func process(image: Image?, error: ErrorType?, forImageTask task: ImageTask) {
        if let image = image, processor = self.delegate.loader(self, processorForRequest:task.request, image: image) {
            let operation = NSBlockOperation { [weak self] in
                self?.imageTask(task, didCompleteWithImage: processor.process(image), error: error)
            }
            self.configuration.processingQueue.addOperation(operation)
            self.executingTasks[task] = ImageLoadState.Processing(operation)
        } else {
            self.imageTask(task, didCompleteWithImage: image, error: error)
        }
    }

    private func imageTask(imageTask: ImageTask, didCompleteWithImage image: Image?, error: ErrorType?) {
        dispatch_async(self.queue) {
            self.manager?.loader(self, task: imageTask, didCompleteWithImage: image, error: error, userInfo: nil)
            self.executingTasks[imageTask] = nil
        }
    }

    public func suspendLoadingFor(task: ImageTask) {
        dispatch_async(self.queue) {
            if let state = self.executingTasks[task] {
                switch state {
                case .Loading(let sessionTask):
                    sessionTask.suspend(task)
                default: break
                }
            }
        }
    }

    public func cancelLoadingFor(task: ImageTask) {
        dispatch_async(self.queue) {
            if let state = self.executingTasks[task] {
                switch state {
                case .Loading(let sessionTask):
                    if sessionTask.cancel(task) {
                        self.removeSessionTask(sessionTask)
                    }
                case .Processing(let operation):
                    operation.cancel()
                }
                self.executingTasks[task] = nil
            }
        }
    }

    private func removeSessionTask(task: ImageSessionTask) {
        if self.sessionTasks[task.key] === task {
            self.sessionTasks[task.key] = nil
        }
    }

    // MARK: Misc

    public func isCacheEquivalent(lhs: ImageRequest, to rhs: ImageRequest) -> Bool {
        return self.delegate.loader(self, isCacheEquivalent: lhs, to: rhs)
    }

    public func invalidate() {
        self.dataLoader.invalidate()
    }

    public func removeAllCachedImages() {
        self.dataLoader.removeAllCachedImages()
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
    case Loading(ImageSessionTask)
    case Processing(NSOperation)
}

// MARK: - ImageSessionTask

private class ImageSessionTask {
    let key: ImageRequestKey
    var dataTask: NSURLSessionTask?
    var executingTasks = Set<ImageTask>()
    var suspendedTasks = Set<ImageTask>()
    var tasks: Set<ImageTask> {
        return self.executingTasks.union(self.suspendedTasks)
    }
    var progress: ImageTaskProgress = ImageTaskProgress()

    init(key: ImageRequestKey) {
        self.key = key
    }

    func resume(task: ImageTask) {
        self.suspendedTasks.remove(task)
        self.executingTasks.insert(task)
        self.dataTask?.resume()
    }

    func cancel(task: ImageTask) -> Bool {
        self.executingTasks.remove(task)
        self.suspendedTasks.remove(task)
        if self.tasks.isEmpty {
            self.dataTask?.cancel()
            self.dataTask = nil
            return true
        }
        return false
    }

    func suspend(task: ImageTask) {
        self.executingTasks.remove(task)
        self.suspendedTasks.insert(task)
        if self.executingTasks.isEmpty {
            self.dataTask?.suspend()
        }
    }

    func complete() {
        self.executingTasks.removeAll()
        self.suspendedTasks.removeAll()
        self.dataTask = nil
    }
}
