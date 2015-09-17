// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

public enum ImageContentMode {
    case AspectFill
    case AspectFit
}

public let ImageMaximumSize = CGSizeMake(CGFloat.max, CGFloat.max)

public typealias ImageTaskCompletion = (ImageResponse) -> Void

public let ImageManagerErrorDomain = "Nuke.ImageManagerErrorDomain"
public let ImageManagerErrorCancelled = -1
public let ImageManagerErrorUnknown = -2


// MARK: - ImageManagerConfiguration

public struct ImageManagerConfiguration {
    public var dataLoader: ImageDataLoading
    public var decoder: ImageDecoding
    public var cache: ImageMemoryCaching?
    public var processor: ImageProcessing?
    public var maxConcurrentPreheatingRequests = 2
    
    public init(dataLoader: ImageDataLoading, decoder: ImageDecoder = ImageDecoder(), cache: ImageMemoryCaching?, processor: ImageProcessing?) {
        self.dataLoader = dataLoader
        self.decoder = decoder
        self.cache = cache
        self.processor = processor
    }
}


// MARK: - ImageManager

public class ImageManager {
    public let configuration: ImageManagerConfiguration
    
    private let imageLoader: ImageManagerLoader
    private var executingTasks = Set<ImageTaskInternal>()
    private var preheatingTasks = [ImageRequestKey: ImageTaskInternal]()
    private let lock = NSRecursiveLock()
    private var preheatingTaskCounter = 0
    private var invalidated = false
    private var needsToExecutePreheatingTasks = false
    
    public init(configuration: ImageManagerConfiguration) {
        self.configuration = configuration
        self.imageLoader = ImageManagerLoader(configuration: configuration)
        self.imageLoader.delegate = self
    }
    
    // MARK: Image Tasks
    
    public func taskWithURL(URL: NSURL, completion: ImageTaskCompletion?) -> ImageTask {
        return self.taskWithRequest(ImageRequest(URL: URL), completion: completion)
    }
    
    public func taskWithRequest(request: ImageRequest, completion: ImageTaskCompletion?) -> ImageTask {
        return ImageTaskInternal(manager: self, request: request, completion: completion)
    }
    
    // MARK: FSM (ImageTaskState)
    
    private func setTaskState(state: ImageTaskState, task: ImageTaskInternal)  {
        if task.isValidNextState(state) {
            self.transitionStateAction(task.state, toState: state, task: task)
            task.state = state
            self.enterStateAction(state, task: task)
        }
    }
    
    private func transitionStateAction(fromState: ImageTaskState, toState: ImageTaskState, task: ImageTaskInternal) {
        if (fromState == .Running && toState == .Cancelled) {
            self.imageLoader.stopLoadingForTask(task)
        }
    }
    
    private func enterStateAction(state: ImageTaskState, task: ImageTaskInternal) {
        if state == .Running {
            if let response = self.imageLoader.cachedResponseForRequest(task.request) {
                task.response = ImageResponse.Success(response.image, ImageResponseInfo(info: response.info, fastResponse: true))
                self.setTaskState(.Completed, task: task)
            } else {
                self.executingTasks.insert(task)
                self.imageLoader.startLoadingForTask(task)
            }
        }
        if state == .Cancelled {
            task.response = ImageResponse.Failure(NSError(domain: ImageManagerErrorDomain, code: ImageManagerErrorCancelled, userInfo: nil))
        }
        if state == .Completed || state == .Cancelled {
            self.executingTasks.remove(task)
            self.setNeedsExecutePreheatingTasks()
            
            let block: dispatch_block_t = {
                assert(task.response != nil)
                task.completion?(task.response!)
            }
            NSThread.isMainThread() ? block() : dispatch_async(dispatch_get_main_queue(), block)
            
            self.taskDidComplete(task)
        }
    }
    
    // MARK: Preheating
    
    public func startPreheatingImages(requests: [ImageRequest]) {
        self.performBlock {
            for request in requests {
                let key = self.imageLoader.preheatingKeyForRequest(request)
                if self.preheatingTasks[key] == nil {
                    let task = ImageTaskInternal(manager: self, request: request, completion: nil)
                    task.tag = self.preheatingTaskCounter++
                    task.preheating = true
                    self.preheatingTasks[key] = task
                }
            }
            self.setNeedsExecutePreheatingTasks()
        }
    }
    
    public func stopPreheatingImages(requests: [ImageRequest]) {
        self.performBlock {
            for request in requests {
                let key = self.imageLoader.preheatingKeyForRequest(request)
                if let task = self.preheatingTasks[key] {
                    self.setTaskState(.Cancelled, task: task)
                }
            }
        }
    }
    
    public func stopPreheatingImages() {
        self.performBlock {
            for task in self.preheatingTasks.values {
                self.setTaskState(.Cancelled, task: task)
            }
        }
    }
    
    private func setNeedsExecutePreheatingTasks() {
        if !self.needsToExecutePreheatingTasks && !self.invalidated {
            self.needsToExecutePreheatingTasks = true
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64((0.15 * Double(NSEC_PER_SEC)))), dispatch_get_main_queue()) {
                [weak self] in self?.performBlock {
                    self?.executePreheatingTasksIfNeeded()
                }
            }
        }
    }
    
    private func executePreheatingTasksIfNeeded() {
        self.needsToExecutePreheatingTasks = false
        var executingTaskCount = self.executingTasks.count
        let sortedPreheatingTasks = self.preheatingTasks.values.sort { $0.tag < $1.tag }
        for task in sortedPreheatingTasks {
            if executingTaskCount > self.configuration.maxConcurrentPreheatingRequests {
                break
            }
            if task.state == .Suspended {
                self.setTaskState(.Running, task: task)
                executingTaskCount++
            }
        }
    }
    
    private func taskDidComplete(task: ImageTaskInternal) {
        if self.preheatingTasks.count > 0 && (task.preheating || task.response?.image != nil) {
            self.preheatingTasks.removeValueForKey(self.imageLoader.preheatingKeyForRequest(task.request))
        }
    }
    
    // MARK: Misc
    
    private func performBlock(@noescape block: Void -> Void) {
        self.lock.lock()
        if !self.invalidated {
            block()
        }
        self.lock.unlock()
    }
    
    public func invalidateAndCancel() {
        self.performBlock {
            self.invalidated = true
            self.preheatingTasks.removeAll()
            self.imageLoader.delegate = nil
            for task in executingTasks {
                self.setTaskState(.Cancelled, task: task)
            }
            self.configuration.dataLoader.invalidate()
        }
    }
}


// MARK: ImageManager: ImageManagerLoaderDelegate

extension ImageManager: ImageManagerLoaderDelegate {
    func imageLoader(imageLoader: ImageManagerLoader, imageTask: ImageTask, didUpdateProgressWithCompletedUnitCount completedUnitCount: Int64, totalUnitCount: Int64) {
        imageTask.progress.totalUnitCount = totalUnitCount
        imageTask.progress.completedUnitCount = completedUnitCount
    }
    
    func imageLoader(imageLoader: ImageManagerLoader, imageTask: ImageTask, didCompleteWithImage image: UIImage?, info: NSDictionary?, error: NSError?) {
        let imageTaskInterval = imageTask as! ImageTaskInternal
        if image != nil {
            imageTaskInterval.response = ImageResponse.Success(image!, ImageResponseInfo(info: info, fastResponse: false))
        } else {
            imageTaskInterval.response = ImageResponse.Failure(error ?? NSError(domain: ImageManagerErrorDomain, code: ImageManagerErrorUnknown, userInfo: nil))
        }
        self.performBlock {
            self.setTaskState(.Completed, task: imageTaskInterval)
        }
    }
}


// MARK: ImageManager: ImageTaskManaging

extension ImageManager: ImageTaskManaging {
    private func resumeManagedTask(task: ImageTaskInternal) {
        self.performBlock {
            self.setTaskState(.Running, task: task)
        }
    }
    
    private func cancelManagedTask(task: ImageTaskInternal) {
        self.performBlock {
            self.setTaskState(.Cancelled, task: task)
        }
    }
}



// MARK: - ImageTaskInternal

private protocol ImageTaskManaging {
    func resumeManagedTask(task: ImageTaskInternal)
    func cancelManagedTask(task: ImageTaskInternal)
}

private class ImageTaskInternal: ImageTask {
    let manager: ImageTaskManaging
    var tag: Int = 0
    var preheating: Bool = false
    
    init(manager: ImageTaskManaging, request: ImageRequest, completion: ImageTaskCompletion?) {
        self.manager = manager
        super.init(request: request, completion: completion)
    }
    
    override func resume() {
        self.manager.resumeManagedTask(self)
    }
    
    override func cancel() {
        self.manager.cancelManagedTask(self)
    }
    
    func isValidNextState(state: ImageTaskState) -> Bool {
        switch (self.state) {
        case .Suspended: return (state == .Running || state == .Cancelled)
        case .Running: return (state == .Completed || state == .Cancelled)
        default: return false
        }
    }
}
