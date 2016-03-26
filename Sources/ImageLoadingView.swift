// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

#if os(OSX)
    import Cocoa
    public typealias View = NSView
#else
    import UIKit
    public typealias View = UIView
#endif

// MARK: - ImageViewLoadingOptions

/// Options for image loading.
public struct ImageViewLoadingOptions {
    /// Custom animations to run when the image is displayed. Default value is nil.
    public var animations: ((ImageLoadingView) -> Void)? = nil
    
    /// If true the loaded image is displayed with animation. Default value is true.
    public var animated = true
    
    /// Custom handler to run when the task completes. Overrides the default completion handler. Default value is nil.
    public var handler: ((ImageLoadingView, ImageTask, ImageResponse, ImageViewLoadingOptions) -> Void)? = nil
    
    /// Default value is nil.
    public var userInfo: Any? = nil

    /// Initializes the receiver.
    public init() {}
}


// MARK: - ImageLoadingView

/// View that supports image loading.
public protocol ImageLoadingView: class {
    /// Cancels the task currently associated with the view.
    func nk_cancelLoading()
    
    /// Loads and displays an image for the given request. Cancels previously started requests.
    func nk_setImageWith(request: ImageRequest, options: ImageViewLoadingOptions) -> ImageTask
    
    /// Gets called when the task that is currently associated with the view completes.
    func nk_imageTask(task: ImageTask, didFinishWithResponse response: ImageResponse, options: ImageViewLoadingOptions)
}

public extension ImageLoadingView {
    /// Loads and displays an image for the given URL. Cancels previously started requests.
    public func nk_setImageWith(URL: NSURL) -> ImageTask {
        return nk_setImageWith(ImageRequest(URL: URL))
    }
    
    /// Loads and displays an image for the given request. Cancels previously started requests.
    public func nk_setImageWith(request: ImageRequest) -> ImageTask {
        return nk_setImageWith(request, options: ImageViewLoadingOptions())
    }
}


// MARK: - ImageDisplayingView

/// View that can display images.
public protocol ImageDisplayingView: class {
    /// Displays a given image.
    func nk_displayImage(image: Image?)

}


// MARK: - Default ImageLoadingView Implementation

/// Default ImageLoadingView implementation.
public extension ImageLoadingView {

    /// Cancels current image task.
    public func nk_cancelLoading() {
        nk_imageLoadingController.cancelLoading()
    }

    /// Loads and displays an image for the given request. Cancels previously started requests.
    public func nk_setImageWith(request: ImageRequest, options: ImageViewLoadingOptions) -> ImageTask {
        return nk_imageLoadingController.setImageWith(request, options: options)
    }

    /// Returns current task.
    public var nk_imageTask: ImageTask? {
        return nk_imageLoadingController.imageTask
    }
    
    /// Returns image loading controller associated with the view.
    public var nk_imageLoadingController: ImageViewLoadingController {
        if let loader = objc_getAssociatedObject(self, &AssociatedKeys.LoadingController) as? ImageViewLoadingController {
            return loader
        }
        let loader = ImageViewLoadingController { [weak self] in
            self?.nk_imageTask($0, didFinishWithResponse: $1, options: $2)
        }
        objc_setAssociatedObject(self, &AssociatedKeys.LoadingController, loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return loader
    }
}

private struct AssociatedKeys {
    static var LoadingController = "nk_imageViewLoadingController"
}

/// Default implementation for image task completion handler.
public extension ImageLoadingView where Self: ImageDisplayingView, Self: View {
    
    /// Default implementation that displays the image and runs animations if necessary.
    public func nk_imageTask(task: ImageTask, didFinishWithResponse response: ImageResponse, options: ImageViewLoadingOptions) {
        if let handler = options.handler {
            handler(self, task, response, options)
            return
        }
        switch response {
        case let .Success(image, info):
            nk_displayImage(image)
            if options.animated && !info.isFastResponse {
                if let animations = options.animations {
                    animations(self) // User provided custom animations
                } else {
                    let animation = CABasicAnimation(keyPath: "opacity")
                    animation.duration = 0.25
                    animation.fromValue = 0
                    animation.toValue = 1
                    let layer: CALayer? = self.layer // Make compiler happy
                    layer?.addAnimation(animation, forKey: "imageTransition")
                }
            }
        default: return
        }
    }
}


// MARK: - ImageLoadingView Conformance

#if os(iOS) || os(tvOS)
    extension UIImageView: ImageDisplayingView, ImageLoadingView {
        /// Displays a given image.
        public func nk_displayImage(image: Image?) {
            self.image = image
        }
    }
#endif

#if os(OSX)
    extension NSImageView: ImageDisplayingView, ImageLoadingView {
        /// Displays a given image.
        public func nk_displayImage(image: Image?) {
            self.image = image
        }
    }
#endif


// MARK: - ImageViewLoadingController

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
