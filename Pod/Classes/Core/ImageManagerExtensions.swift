// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImageManager {
    private static var sharedManagerIvar: ImageManager!
    private static var lock = OS_SPINLOCK_INIT
    private static var token: dispatch_once_t = 0
    
    public class func shared() -> ImageManager {
        var manager: ImageManager
        dispatch_once(&token) {
            if self.sharedManagerIvar == nil {
                let conf = ImageManagerConfiguration(dataLoader: ImageDataLoader(), cache: ImageMemoryCache(), processor: ImageProcessor())
                self.sharedManagerIvar = ImageManager(configuration: conf)
            }
        }
        OSSpinLockLock(&lock)
        manager = sharedManagerIvar
        OSSpinLockUnlock(&lock)
        return manager
    }
    
    public class func setShared(manager: ImageManager) {
        OSSpinLockLock(&lock)
        sharedManagerIvar = manager
        OSSpinLockUnlock(&lock)
    }
}
