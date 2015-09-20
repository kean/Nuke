// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageManaging

public protocol ImageManaging {
    func taskWithRequest(request: ImageRequest) -> ImageTask
    func invalidateAndCancel()
    func removeAllCachedImages()
}

// MARK: - ImagePreheating

public protocol ImagePreheating {
    func startPreheatingImages(requests: [ImageRequest])
    func stopPreheatingImages(requests: [ImageRequest])
    func stopPreheatingImages()
}

// MARK: - ImageManaging (Convenience)

public extension ImageManaging {
    func taskWithURL(URL: NSURL) -> ImageTask {
        return self.taskWithRequest(ImageRequest(URL: URL))
    }
    
    func taskWithURL(URL: NSURL, completion: ImageTaskCompletion?) -> ImageTask {
        let task = self.taskWithURL(URL)
        if completion != nil { task.completion(completion!) }
        return task
    }
    
    func taskWithRequest(request: ImageRequest, completion: ImageTaskCompletion?) -> ImageTask {
        let task = self.taskWithRequest(request)
        if completion != nil { task.completion(completion!) }
        return task
    }
}
