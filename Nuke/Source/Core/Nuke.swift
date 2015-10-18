// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - Convenience

/** Creates a task with a given URL. After you create a task, you start it by calling its resume method.
*/
public func taskWithURL(URL: NSURL, completion: ImageTaskCompletion? = nil) -> ImageTask {
    return ImageManager.shared.taskWithURL(URL, completion: completion)
}

/** Creates a task with a given request. After you create a task, you start it by calling its resume method.
*/
public func taskWithRequest(request: ImageRequest, completion: ImageTaskCompletion? = nil) -> ImageTask {
    return ImageManager.shared.taskWithRequest(request, completion: completion)
}

/** Prepares images for the given requests for later use.

When you call this method, ImageManager starts to load and cache images for the given requests. ImageManager caches images with the exact target size, content mode, and filters. At any time afterward, you can create tasks with equivalent requests.
*/
public func startPreheatingImages(requests: [ImageRequest]) {
    ImageManager.shared.startPreheatingImages(requests)
}

/** Stop preheating for the given requests. The request parameters should match the parameters used in startPreheatingImages method.
*/
public func stopPreheatingImages(requests: [ImageRequest]) {
    ImageManager.shared.stopPreheatingImages(requests)
}

/** Stops all preheating tasks.
*/
public func stopPreheatingImages() {
    ImageManager.shared.stopPreheatingImages()
}

// MARK: - Internal

#if os(OSX)
    import Cocoa
    public typealias Image = NSImage
#else
    import UIKit
    public typealias Image = UIImage
#endif


internal func dispathOnMainThread(closure: (Void) -> Void) {
    NSThread.isMainThread() ? closure() : dispatch_async(dispatch_get_main_queue(), closure)
}

internal extension NSOperationQueue {
    convenience init(maxConcurrentOperationCount: Int) {
        self.init()
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
    }
}
