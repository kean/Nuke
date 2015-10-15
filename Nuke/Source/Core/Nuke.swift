// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - Convenience

public func taskWithURL(URL: NSURL, completion: ImageTaskCompletion? = nil) -> ImageTask {
    return ImageManager.shared.taskWithURL(URL, completion: completion)
}

public func taskWithRequest(request: ImageRequest, completion: ImageTaskCompletion? = nil) -> ImageTask {
    return ImageManager.shared.taskWithRequest(request, completion: completion)
}

public func invalidateAndCancel() {
    ImageManager.shared.invalidateAndCancel()
}

public func removeAllCachedImages() {
    ImageManager.shared.removeAllCachedImages()
}

public func startPreheatingImages(requests: [ImageRequest]) {
    ImageManager.shared.startPreheatingImages(requests)
}

public func stopPreheatingImages(requests: [ImageRequest]) {
    ImageManager.shared.stopPreheatingImages(requests)
}

public func stopPreheatingImages() {
    ImageManager.shared.stopPreheatingImages()
}

// MARK: -

#if os(OSX)
    import Cocoa
    public typealias Image = NSImage
#else
    import UIKit
    public typealias Image = UIImage
#endif

// MARK: - Internal

internal func dispathOnMainThread(block: (Void) -> Void) {
    NSThread.isMainThread() ? block() : dispatch_async(dispatch_get_main_queue(), block)
}

internal extension NSOperationQueue {
    convenience init(maxConcurrentOperationCount: Int) {
        self.init()
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
    }
}
