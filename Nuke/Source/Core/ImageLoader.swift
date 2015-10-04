// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import UIKit

public protocol ImageLoading: class {
    weak var delegate: ImageLoadingDelegate? { get set }
    func startLoadingForTask(task: ImageTask)
    func stopLoadingForTask(imageTask: ImageTask)
    func isRequestCacheEquivalent(lhs: ImageRequest, toRequest rhs: ImageRequest) -> Bool
    func invalidate()
    func removeAllCachedImages()
}

public protocol ImageLoadingDelegate: class {
    func imageLoader(imageLoader: ImageLoading, imageTask: ImageTask, didUpdateProgressWithCompletedUnitCount completedUnitCount: Int64, totalUnitCount: Int64)
    func imageLoader(imageLoader: ImageLoading, imageTask: ImageTask, didCompleteWithImage image: UIImage?, error: ErrorType?)
}

public struct ImageLoaderConfiguration {
    public var dataLoader: ImageDataLoading
    public var decoder: ImageDecoding
    public var maxConcurrentTaskCount = 8
    public init(dataLoader: ImageDataLoading, decoder: ImageDecoding = ImageDecoder()) {
        self.dataLoader = dataLoader
        self.decoder = decoder
    }
}

public class ImageLoader: ImageLoading {
    public weak var delegate: ImageLoadingDelegate?
    public let configuration: ImageLoaderConfiguration
    
    private var dataLoader: ImageDataLoading {
        return self.configuration.dataLoader
    }
    private var pendingTasks = [ImageTask]()
    private var executingTasks = [ImageTask : ImageLoadState]()
    private var sessionTasks = [ImageRequestKey : ImageSessionTask]()
    private let queue = dispatch_queue_create("ImageLoader-InternalSerialQueue", DISPATCH_QUEUE_SERIAL)
    private let decodingQueue = NSOperationQueue(maxConcurrentOperationCount: 1)
    private let processingQueue = NSOperationQueue(maxConcurrentOperationCount: 2)
    
    public init(configuration: ImageLoaderConfiguration) {
        self.configuration = configuration
    }
    
    public func startLoadingForTask(task: ImageTask) {
        dispatch_async(self.queue) {
            self.pendingTasks.append(task)
            self.executePendingTasks()
        }
    }
    
    private func executePendingTasks() {
        func shouldExecuteNextPendingTask() -> Bool {
            return self.executingTasks.count < self.configuration.maxConcurrentTaskCount
        }
        func dequeueNextPendingTask() -> ImageTask? {
            return self.pendingTasks.isEmpty ? nil : self.pendingTasks.removeFirst()
        }
        while shouldExecuteNextPendingTask() {
            guard let task = dequeueNextPendingTask() else  {
                return
            }
            self.startSessionTaskForTask(task)
        }
    }
    
    private func startSessionTaskForTask(task: ImageTask) {
        let key = ImageRequestKey(task.request, owner: self)
        var sessionTask: ImageSessionTask! = self.sessionTasks[key]
        if sessionTask == nil {
            sessionTask = ImageSessionTask(key: key)
            let dataTask = self.dataLoader.imageDataTaskWithURL(task.request.URL, progressHandler: { [weak self] completedUnits, totalUnits in
                self?.sessionTask(sessionTask, didUpdateProgressWithCompletedUnitCount: completedUnits, totalUnitCount: totalUnits)
            }, completionHandler: { [weak self] data, _, error in
                self?.sessionTask(sessionTask, didCompleteWithData: data, error: error)
            })
            dataTask.resume()
            sessionTask.dataTask = dataTask
            self.sessionTasks[key] = sessionTask
        } else {
            self.delegate?.imageLoader(self, imageTask: task, didUpdateProgressWithCompletedUnitCount: sessionTask.completedUnitCount, totalUnitCount: sessionTask.completedUnitCount)
        }
        self.executingTasks[task] = ImageLoadState.Loading(sessionTask)
        sessionTask.tasks.append(task)
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
            self.decodingQueue.addOperationWithBlock { [weak self] in
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
            sessionTask.tasks.removeAll()
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
            self.processingQueue.addOperation(operation)
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
            self.delegate?.imageLoader(self, imageTask: imageTask, didCompleteWithImage: image, error: error)
            self.executingTasks[imageTask] = nil
            self.executePendingTasks()
        }
    }
    
    public func stopLoadingForTask(imageTask: ImageTask) {
        dispatch_async(self.queue) {
            if let state = self.executingTasks[imageTask] {
                switch state {
                case .Loading(let sessionTask):
                    if let index = (sessionTask.tasks.indexOf { $0 === imageTask }) {
                        sessionTask.tasks.removeAtIndex(index)
                    }
                    if sessionTask.tasks.isEmpty {
                        sessionTask.dataTask?.cancel()
                        sessionTask.dataTask = nil
                        self.removeSessionTask(sessionTask)
                    }
                case .Processing(let operation):
                    operation.cancel()
                }
                self.executingTasks[imageTask] = nil
                self.executePendingTasks()
            } else if let index = (self.pendingTasks.indexOf { $0 === imageTask }) {
                self.pendingTasks.removeAtIndex(index)
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
    internal func isImageRequestKey(lhs: ImageRequestKey, equalToKey rhs: ImageRequestKey) -> Bool {
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
    var tasks = [ImageTask]()
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
