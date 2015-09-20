// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import UIKit

public let ImageManagerErrorDomain = "Nuke.ImageManagerErrorDomain"
public let ImageManagerErrorCancelled = -1
public let ImageManagerErrorUnknown = -2

// MARK: - ImageManagerConfiguration

public struct ImageManagerConfiguration {
    public var dataLoader: ImageDataLoading
    public var decoder: ImageDecoding
    public var cache: ImageMemoryCaching?
    public var maxConcurrentPreheatingTasks = 2
    
    public init(dataLoader: ImageDataLoading, decoder: ImageDecoding = ImageDecoder(), cache: ImageMemoryCaching? = ImageMemoryCache()) {
        self.dataLoader = dataLoader
        self.decoder = decoder
        self.cache = cache
    }
}

// MARK: - ImageManager

public class ImageManager: ImageManaging, ImagePreheating, ImageManagerLoaderDelegate, ImageTaskManaging {
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
    
    // MARK: ImageManaging
    
    public func taskWithRequest(request: ImageRequest) -> ImageTask {
        return ImageTaskInternal(manager: self, request: request)
    }
    
    public func invalidateAndCancel() {
        self.performBlock {
            self.imageLoader.delegate = nil
            self.cancelTasks(Array(self.executingTasks))
            self.preheatingTasks.removeAll()
            self.configuration.dataLoader.invalidate()
            self.invalidated = true
        }
    }
    
    public func removeAllCachedImages() {
        self.configuration.cache?.removeAllCachedImages()
        self.configuration.dataLoader.removeAllCachedImages()
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
        if fromState == .Running && toState == .Cancelled {
            self.imageLoader.stopLoadingForTask(task)
        }
    }
    
    private func enterStateAction(state: ImageTaskState, task: ImageTaskInternal) {
        if state == .Running {
            if let response = self.imageLoader.cachedResponseForRequest(task.request) {
                task.response = ImageResponse.Success(response.image, ImageResponseInfo(fastResponse: true, userInfo: response.userInfo))
                self.setState(.Completed, forTask: task)
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
            
            let completions = task.completions
            self.dispatchBlock {
                assert(task.response != nil)
                for completion in completions {
                    completion(task.response!)
                }
            }
        }
    }
    
    private func dispatchBlock(block: (Void) -> Void) {
        NSThread.isMainThread() ? block() : dispatch_async(dispatch_get_main_queue(), block)
    }
    
    // MARK: ImagePreheating
    
    public func startPreheatingImages(requests: [ImageRequest]) {
        self.performBlock {
            for request in requests {
                let key = self.imageLoader.preheatingKeyForRequest(request)
                if self.preheatingTasks[key] == nil {
                    let task = ImageTaskInternal(manager: self, request: request)
                    task.tag = self.preheatingTaskCounter++
                    task.completion { [weak self] _ in
                        self?.preheatingTasks[key] = nil
                    }
                    self.preheatingTasks[key] = task
                }
            }
            self.setNeedsExecutePreheatingTasks()
        }
    }
    
    public func stopPreheatingImages(requests: [ImageRequest]) {
        self.performBlock {
            self.cancelTasks(requests.flatMap {
                return self.preheatingTasks[self.imageLoader.preheatingKeyForRequest($0)]
                })
        }
    }
    
    public func stopPreheatingImages() {
        self.performBlock {
            self.cancelTasks(Array(self.preheatingTasks.values))
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
            if executingTaskCount > self.configuration.maxConcurrentPreheatingTasks {
                break
            }
            if task.state == .Suspended {
                self.setState(.Running, forTask: task)
                executingTaskCount++
            }
        }
    }
    
    // MARK: ImageManagerLoaderDelegate
    
    internal func imageLoader(imageLoader: ImageManagerLoader, imageTask: ImageTask, didUpdateProgressWithCompletedUnitCount completedUnitCount: Int64, totalUnitCount: Int64) {
        imageTask.progress.totalUnitCount = totalUnitCount
        imageTask.progress.completedUnitCount = completedUnitCount
    }
    
    internal func imageLoader(imageLoader: ImageManagerLoader, imageTask: ImageTask, didCompleteWithImage image: UIImage?, error: ErrorType?) {
        let imageTaskInterval = imageTask as! ImageTaskInternal
        if image != nil {
            imageTaskInterval.response = ImageResponse.Success(image!, ImageResponseInfo(fastResponse: false))
        } else {
            imageTaskInterval.response = ImageResponse.Failure(error ?? NSError(domain: ImageManagerErrorDomain, code: ImageManagerErrorUnknown, userInfo: nil))
        }
        self.performBlock {
            self.setState(.Completed, forTask: imageTaskInterval)
        }
    }
    
    // MARK: ImageTaskManaging
    
    private func resumeManagedTask(task: ImageTaskInternal) {
        self.performBlock {
            self.setState(.Running, forTask: task)
        }
    }
    
    private func cancelManagedTask(task: ImageTaskInternal) {
        self.performBlock {
            self.setState(.Cancelled, forTask: task)
        }
    }
    
    private func addCompletion(completion: ImageTaskCompletion, forTask task: ImageTaskInternal) {
        self.performBlock {
            if task.state == .Completed || task.state == .Cancelled {
                dispatchBlock {
                    assert(task.response != nil)
                    completion(task.response!)
                }
            } else {
                task.completions.append(completion)
            }
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
    
    private func cancelTasks(tasks: [ImageTaskInternal]) {
        tasks.forEach { self.setState(.Cancelled, forTask: $0) }
    }
}

// MARK: - ImageManager (Shared)

public extension ImageManager {
    private static var sharedManagerIvar: ImageManager = ImageManager(configuration: ImageManagerConfiguration(dataLoader: ImageDataLoader()))
    private static var lock = OS_SPINLOCK_INIT
    private static var token: dispatch_once_t = 0
    
    public class var shared: ImageManager {
        set {
        OSSpinLockLock(&lock)
        sharedManagerIvar = newValue
        OSSpinLockUnlock(&lock)
        }
        get {
            var manager: ImageManager
            OSSpinLockLock(&lock)
            manager = sharedManagerIvar
            OSSpinLockUnlock(&lock)
            return manager
        }
    }
}

// MARK: - ImageTaskInternal

private protocol ImageTaskManaging {
    func resumeManagedTask(task: ImageTaskInternal)
    func cancelManagedTask(task: ImageTaskInternal)
    func addCompletion(completion: ImageTaskCompletion, forTask task: ImageTaskInternal)
}

private class ImageTaskInternal: ImageTask {
    let manager: ImageTaskManaging
    var tag = 0
    var completions = [ImageTaskCompletion]()
    
    init(manager: ImageTaskManaging, request: ImageRequest) {
        self.manager = manager
        super.init(request: request)
    }
    
    override func resume() -> Self {
        self.manager.resumeManagedTask(self)
        return self
    }
    
    override func cancel() -> Self {
        self.manager.cancelManagedTask(self)
        return self
    }
    
    override func completion(completion: ImageTaskCompletion) -> Self {
        self.manager.addCompletion(completion, forTask: self)
        return self
    }
    
    func isValidNextState(state: ImageTaskState) -> Bool {
        switch (self.state) {
        case .Suspended: return (state == .Running || state == .Cancelled)
        case .Running: return (state == .Completed || state == .Cancelled)
        default: return false
        }
    }
}
