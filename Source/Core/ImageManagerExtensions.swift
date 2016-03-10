// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageManager (Convenience)

/// Convenience methods for ImageManager.
public extension ImageManager {
    // MARK: Adding Tasks (Convenience)

    /// Creates a task with a given request. For more info see `taskWith(_)` methpd.
    func taskWith(URL: NSURL, completion: ImageTaskCompletion? = nil) -> ImageTask {
        return self.taskWith(ImageRequest(URL: URL), completion: completion)
    }

    /// Creates a task with a given request. For more info see `taskWith(_)` methpd.
    func taskWith(request: ImageRequest, completion: ImageTaskCompletion?) -> ImageTask {
        let task = self.taskWith(request)
        if completion != nil { task.completion(completion!) }
        return task
    }
}

// MARK: - ImageManager (Shared)

/// Manages shared ImageManager instance.
public extension ImageManager {
    private static var sharedManagerIvar: ImageManager = ImageManager(configuration: ImageManagerConfiguration(dataLoader: ImageDataLoader()))
    private static var lock = OS_SPINLOCK_INIT
    private static var token: dispatch_once_t = 0
    
    // MARK: Shared Manager
    
    /// The shared image manager. This property as well as all `ImageManager` methods are thread safe.
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
