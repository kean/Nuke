// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

/** Manages execution of image tasks for image loading view.
*/
public class ImageViewLoadingController {
    /** Current image task
    */
    public var imageTask: ImageTask?
    
    /** Handler that gets called each time current imageTask completes or cancels.
    */
    public var handler: (ImageTask, ImageResponse, ImageViewLoadingOptions?) -> Void
    
    public var manager: ImageManager = ImageManager.shared
    
    deinit {
        self.cancelLoading()
    }
    
    public init(handler: (ImageTask, ImageResponse, ImageViewLoadingOptions?) -> Void) {
        self.handler = handler
    }
    
    public func cancelLoading() {
        if let task = self.imageTask {
            self.imageTask = nil
            // Cancel task after delay to allow new tasks to subsribe to exiting NSURLSessionTasks before they get cancelled.
            dispatch_async(dispatch_get_main_queue()) {
                task.cancel()
            }
        }
    }
    
    public func setImageWithRequest(request: ImageRequest, options: ImageViewLoadingOptions?)  -> ImageTask {
        self.cancelLoading()
        let task = self.manager.taskWithRequest(request)
        task.completion { [weak self, weak task] in
            guard let task = task where task == self?.imageTask else {
                return
            }
            self?.handler(task, $0, options)
        }
        self.imageTask = task
        task.resume()
        return task
    }
}
