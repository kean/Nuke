// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import UIKit

extension ImageManager {
    private static var sharedManagerIvar: ImageManaging = ImageManager(configuration: ImageManagerConfiguration(dataLoader: ImageDataLoader()))
    private static var lock = OS_SPINLOCK_INIT
    private static var token: dispatch_once_t = 0
    
    public class func shared() -> ImageManaging {
        var manager: ImageManaging
        OSSpinLockLock(&lock)
        manager = sharedManagerIvar
        OSSpinLockUnlock(&lock)
        return manager
    }
    
    public class func setShared(manager: ImageManaging) {
        OSSpinLockLock(&lock)
        sharedManagerIvar = manager
        OSSpinLockUnlock(&lock)
    }
}
