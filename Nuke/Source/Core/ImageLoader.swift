// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import UIKit

// MARK: - ImageLoading

public protocol ImageLoading: class {
    weak var delegate: ImageLoadingDelegate? { get set }
    func resumeLoadingForTask(task: ImageTask)
    func suspendLoadingForTask(task: ImageTask)
    func cancelLoadingForTask(task: ImageTask)
    func isRequestCacheEquivalent(lhs: ImageRequest, toRequest rhs: ImageRequest) -> Bool
    func invalidate()
    func removeAllCachedImages()
}

// MARK: - ImageLoadingDelegate

public protocol ImageLoadingDelegate: class {
    func imageLoader(imageLoader: ImageLoading, imageTask: ImageTask, didUpdateProgressWithCompletedUnitCount completedUnitCount: Int64, totalUnitCount: Int64)
    func imageLoader(imageLoader: ImageLoading, imageTask: ImageTask, didCompleteWithImage image: UIImage?, error: ErrorType?, userInfo: Any?)
}

// MARK: - ImageLoaderConfiguration

public struct ImageLoaderConfiguration {
    public var dataLoader: ImageDataLoading
    public var decoder: ImageDecoding
    public var decodingQueue = NSOperationQueue(maxConcurrentOperationCount: 1)
    public var processingQueue = NSOperationQueue(maxConcurrentOperationCount: 2)
    
    public init(dataLoader: ImageDataLoading, decoder: ImageDecoding = ImageDecoder()) {
        self.dataLoader = dataLoader
        self.decoder = decoder
    }
}

// MARK: - ImageLoader

/*! Implements image loading using objects conforming to ImageDataLoading, ImageDecoding and ImageProcessing protocols. Reuses data tasks for multiple equivalent image tasks.
*/
public class ImageLoader: ImageLoading {
    public weak var delegate: ImageLoadingDelegate?
    public let configuration: ImageLoaderConfiguration
    
    private var dataLoader: ImageDataLoading {
        return self.configuration.dataLoader
    }
    private var executingTasks = [ImageTask : ImageLoadState]()
    private var sessionTasks = [ImageRequestKey : ImageSessionTask]()
    private let queue = dispatch_queue_create("ImageLoader-InternalSerialQueue", DISPATCH_QUEUE_SERIAL)
    
    public init(configuration: ImageLoaderConfiguration) {
        self.configuration = configuration
    }
    
    public func resumeLoadingForTask(task: ImageTask) {
        dispatch_async(self.queue) {
            let key = ImageRequestKey(task.request, owner: self)
            var sessionTask: ImageSessionTask! = self.sessionTasks[key]
            if sessionTask == nil {
                sessionTask = self.createSessionTaskWithRequest(task.request, key: key)
                self.sessionTasks[key] = sessionTask
            } else {
                self.delegate?.imageLoader(self, imageTask: task, didUpdateProgressWithCompletedUnitCount: sessionTask.completedUnitCount, totalUnitCount: sessionTask.totalUnitCount)
            }
            self.executingTasks[task] = ImageLoadState.Loading(sessionTask)
            sessionTask.suspendedTasks.remove(task)
            sessionTask.executingTasks.insert(task)
            sessionTask.dataTask?.resume()
        }
    }

    private func createSessionTaskWithRequest(request: ImageRequest, key: ImageRequestKey) -> ImageSessionTask {
        let sessionTask = ImageSessionTask(key: key)
        let dataTask = self.dataLoader.imageDataTaskWithURL(request.URL, progressHandler: { [weak self] completedUnits, totalUnits in
            self?.sessionTask(sessionTask, didUpdateProgressWithCompletedUnitCount: completedUnits, totalUnitCount: totalUnits)
        }, completionHandler: { [weak self] data, _, error in
            self?.sessionTask(sessionTask, didCompleteWithData: data, error: error)
        })
        sessionTask.dataTask = dataTask
        return sessionTask
    }

    private func sessionTask(sessionTask: ImageSessionTask, didUpdateProgressWithCompletedUnitCount completedUnitCount: Int64, totalUnitCount: Int64) {
        dispatch_async(self.queue) {
            sessionTask.totalUnitCount = totalUnitCount
            sessionTask.completedUnitCount = completedUnitCount
            for imageTask in sessionTask.tasks {
                self.delegate?.imageLoader(self, imageTask: imageTask, didUpdateProgressWithCompletedUnitCount: completedUnitCount, totalUnitCount: totalUnitCount)
            }
        }
    }

    private func sessionTask(sessionTask: ImageSessionTask, didCompleteWithData data: NSData?, error: ErrorType?) {
        if let data = data {
            self.configuration.decodingQueue.addOperationWithBlock { [weak self] in
                let image = self?.configuration.decoder.imageWithData(data)
                self?.sessionTask(sessionTask, didCompleteWithImage: image, error: error)
            }
        } else {
            self.sessionTask(sessionTask, didCompleteWithImage: nil, error: error)
        }
    }
    
    private func sessionTask(sessionTask: ImageSessionTask, didCompleteWithImage image: UIImage?, error: ErrorType?) {
        dispatch_async(self.queue) {
            for imageTask in sessionTask.tasks {
                self.processImage(image, error: error, forImageTask: imageTask)
            }
            sessionTask.suspendedTasks.removeAll()
            sessionTask.executingTasks.removeAll()
            sessionTask.dataTask = nil
            self.removeSessionTask(sessionTask)
        }
    }
    
    private func processImage(image: UIImage?, error: ErrorType?, forImageTask imageTask: ImageTask) {
        if let image = image, processor = self.processorForRequest(imageTask.request) {
            let operation = NSBlockOperation { [weak self] in
                let processedImage = processor.processImage(image)
                self?.imageTask(imageTask, didCompleteWithImage: processedImage, error: error)
            }
            self.configuration.processingQueue.addOperation(operation)
            self.executingTasks[imageTask] = ImageLoadState.Processing(operation)
        } else {
            self.imageTask(imageTask, didCompleteWithImage: image, error: error)
        }
    }
    
    private func processorForRequest(request: ImageRequest) -> ImageProcessing? {
        var processors = [ImageProcessing]()
        if request.shouldDecompressImage {
            processors.append(ImageDecompressor(targetSize: request.targetSize, contentMode: request.contentMode))
        }
        if let processor = request.processor {
            processors.append(processor)
        }
        return processors.isEmpty ? nil : ImageProcessorComposition(processors: processors)
    }
    
    private func imageTask(imageTask: ImageTask, didCompleteWithImage image: UIImage?, error: ErrorType?) {
        dispatch_async(self.queue) {
            self.delegate?.imageLoader(self, imageTask: imageTask, didCompleteWithImage: image, error: error, userInfo: nil)
            self.executingTasks[imageTask] = nil
        }
    }

    public func suspendLoadingForTask(task: ImageTask) {
        dispatch_async(self.queue) {
            if let state = self.executingTasks[task] {
                switch state {
                case .Loading(let sessionTask):
                    sessionTask.executingTasks.remove(task)
                    sessionTask.suspendedTasks.insert(task)
                    if sessionTask.executingTasks.isEmpty {
                        sessionTask.dataTask?.suspend()
                    }
                default: break
                }
            }
        }
    }
    
    public func cancelLoadingForTask(task: ImageTask) {
        dispatch_async(self.queue) {
            if let state = self.executingTasks[task] {
                switch state {
                case .Loading(let sessionTask):
                    sessionTask.executingTasks.remove(task)
                    sessionTask.suspendedTasks.remove(task)
                    if sessionTask.tasks.isEmpty {
                        sessionTask.dataTask?.cancel()
                        sessionTask.dataTask = nil
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
    
    public func isRequestCacheEquivalent(lhs: ImageRequest, toRequest rhs: ImageRequest) -> Bool {
        guard self.dataLoader.isRequestCacheEquivalent(lhs, toRequest: rhs) else {
            return false
        }
        switch (self.processorForRequest(lhs), self.processorForRequest(rhs)) {
        case (.Some(let lhs), .Some(let rhs)): return lhs.isEquivalentToProcessor(rhs)
        case (.None, .None): return true
        default: return false
        }
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
    public func isImageRequestKey(lhs: ImageRequestKey, equalToKey rhs: ImageRequestKey) -> Bool {
        return self.dataLoader.isRequestLoadEquivalent(lhs.request, toRequest: rhs.request)
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
    var totalUnitCount: Int64 = 0
    var completedUnitCount: Int64 = 0
    
    init(key: ImageRequestKey) {
        self.key = key
    }
}

// MARK: - Misc

extension NSOperationQueue {
    private convenience init(maxConcurrentOperationCount: Int) {
        self.init()
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
    }
}
