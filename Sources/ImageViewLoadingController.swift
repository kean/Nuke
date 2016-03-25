// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Manages execution of image tasks for image loading view.
public class ImageViewLoadingController {
    /// Current task.
    public var imageTask: ImageTask?
    
    /// Handler that gets called each time current task completes.
    public var handler: (ImageTask, ImageResponse, ImageViewLoadingOptions) -> Void
    
    /// The image manager used for creating tasks. The shared manager is used by default.
    public var manager: ImageManager = ImageManager.shared
    
    deinit {
        cancelLoading()
    }

    /// Initializes the receiver with a given handler.
    public init(handler: (ImageTask, ImageResponse, ImageViewLoadingOptions) -> Void) {
        self.handler = handler
    }
    
    /// Cancels current task.
    public func cancelLoading() {
        if let task = imageTask {
            imageTask = nil
            // Cancel task after delay to allow new tasks to subscribe to the existing NSURLSessionTask.
            dispatch_async(dispatch_get_main_queue()) {
                task.cancel()
            }
        }
    }

    /// Creates a task, subscribes to it and resumes it.
    public func setImageWith(request: ImageRequest, options: ImageViewLoadingOptions) -> ImageTask {
        return setImageWith(manager.taskWith(request), options: options)
    }

    /// Subscribes for a given task and resumes it.
    public func setImageWith(task: ImageTask, options: ImageViewLoadingOptions) -> ImageTask {
        cancelLoading()
        imageTask = task
        task.completion { [weak self, weak task] in
            if let task = task where task == self?.imageTask {
                self?.handler(task, $0, options)
            }
        }
        task.resume()
        return task
    }
}
