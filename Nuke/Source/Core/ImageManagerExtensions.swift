// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageManager (Convenience)

public extension ImageManager {
    func taskWithURL(URL: NSURL, completion: ImageTaskCompletion? = nil) -> ImageTask {
        return self.taskWithRequest(ImageRequest(URL: URL), completion: completion)
    }
    
    func taskWithRequest(request: ImageRequest, completion: ImageTaskCompletion?) -> ImageTask {
        let task = self.taskWithRequest(request)
        if completion != nil { task.completion(completion!) }
        return task
    }
}

// MARK: - ImageManager (Shared)

public extension ImageManager {
    private static var sharedManagerIvar: ImageManager = ImageManager(configuration: ImageManagerConfiguration(dataLoader: ImageDataLoader()))
    private static var lock = OS_SPINLOCK_INIT
    private static var token: dispatch_once_t = 0
    
    /** The shared image manager. This property as well as all `ImageManager` methods are thread safe.
     */
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
