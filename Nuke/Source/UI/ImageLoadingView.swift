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

// MARK: - ImageLoadingView

public struct ImageViewLoadingOptions {
    /**
     Custom animations to run when the image is displayed. Default value is nil.
     
     This closure is not called if the response is from memory cache (`isFastResponse`) or if the `animated` property of the reciever is set to `false`. Use `handler` property if you need more control.
     */
    public var animations: ((ImageLoadingView) -> Void)? = nil
    
    /** If true the loaded image is displayed with an animation. Default value is true.
     */
    public var animated = true
    
    /* Custom handler to run when the image task completes. Overrides the default completion handling. Default value is nil.
    */
    public var handler: ((ImageLoadingView, ImageTask, ImageResponse, ImageViewLoadingOptions) -> Void)? = nil
    
    /** Default value is nil.
     */
    public var userInfo: Any? = nil
    
    public init() {}
}

/** View that supports image loading.
 */
public protocol ImageLoadingView: class {
    /** Cancels the task currently associated with the view.
     */
    func nk_cancelLoading()
    
    /** Loads and displays an image for the given request. Cancels previously started requests.
     */
    func nk_setImageWith(request: ImageRequest, options: ImageViewLoadingOptions) -> ImageTask
    
    /** Gets called when the task that is currently associated with the view completes.
     
     See https://github.com/kean/Nuke/issues/38 for more info about overriding this method.
     */
    func nk_imageTask(task: ImageTask, didFinishWithResponse response: ImageResponse, options: ImageViewLoadingOptions)
}

public extension ImageLoadingView where Self: View {
    /** Loads and displays an image for the given URL. Cancels previously started requests.
     
     Uses ImageContentMode.AspectFill, and current view size multiplied by screen scaling factor as an image target size.
     */
    public func nk_setImageWith(URL: NSURL) -> ImageTask {
        return self.nk_setImageWith(ImageRequest(URL: URL, targetSize: self.nk_targetSize(), contentMode: .AspectFill))
    }
    
    /** Loads and displays an image for the given request. Cancels previously started requests.
     */
    public func nk_setImageWith(request: ImageRequest) -> ImageTask {
        return self.nk_setImageWith(request, options: ImageViewLoadingOptions())
    }
}

public extension View {
    /** Returns image target size (in pixels) for the view. Target size is calculated by multiplying view's size by screen scale factor.
     */
    public func nk_targetSize() -> CGSize {
        let size = self.bounds.size
        #if os(iOS) || os(tvOS)
            let scale = UIScreen.mainScreen().scale
        #elseif os(OSX)
            let scale = NSScreen.mainScreen()?.backingScaleFactor ?? 1.0
        #endif
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

// MARK: - ImageDisplayingView

/** View that supports displaying images.
*/
public protocol ImageDisplayingView: class {
    var nk_image: Image? { get set }
}

/** Default value is 0.25.
*/
public var ImageViewDefaultAnimationDuration = 0.25
// FIXME: Remove `Default` from the name or remove this var all together.

/** Provides default implementation for image task completion handler.
 */
public extension ImageLoadingView where Self: ImageDisplayingView, Self: View {
    public func nk_setImageWith(request: ImageRequest, options: ImageViewLoadingOptions = ImageViewLoadingOptions(), placeholder: Image?) -> ImageTask {
        if let placeholder = placeholder {
            self.nk_image = placeholder
        }
        return self.nk_setImageWith(request, options: options)
    }
    
    /** Default implementation that displays the image and runs animations if necessary.
     */
    public func nk_imageTask(task: ImageTask, didFinishWithResponse response: ImageResponse, options: ImageViewLoadingOptions) {
        if let handler = options.handler {
            handler(self, task, response, options)
            return
        }
        switch response {
        case let .Success(image, info):
            // FIXME: Make nk_image write only, keep only basic opacity transition
            let previousImage = self.nk_image
            self.nk_image = image
            guard options.animated && !info.isFastResponse else {
                return
            }
            if let animations = options.animations {
                animations(self) // User provided custom animations
            } else {
                let layer: CALayer? = self.layer // Make compiler happy
                if previousImage == nil {
                    let animation = CABasicAnimation(keyPath: "opacity")
                    animation.duration = ImageViewDefaultAnimationDuration
                    animation.fromValue = 0
                    animation.toValue = 1
                    layer?.addAnimation(animation, forKey: "imageTransition")
                } else {
                    let animation = CATransition()
                    animation.duration = ImageViewDefaultAnimationDuration
                    animation.type = kCATransitionFade
                    layer?.addAnimation(animation, forKey: "imageTransition")
                }
            }
        default: return
        }
    }
}

// MARK: - Default ImageLoadingView Implementation

/** Default ImageLoadingView implementation.
*/
public extension ImageLoadingView {
    
    // MARK: ImageLoadingView
    
    public func nk_cancelLoading() {
        self.nk_imageLoadingController.cancelLoading()
    }
    
    public func nk_setImageWith(request: ImageRequest, options: ImageViewLoadingOptions) -> ImageTask {
        return self.nk_imageLoadingController.setImageWith(request, options: options)
    }
    
    // MARK: Helpers
    
    /** Returns current task.
    */
    public var nk_imageTask: ImageTask? {
        return self.nk_imageLoadingController.imageTask
    }
    
    /** Returns image loading controller associated with the view.
     */
    public var nk_imageLoadingController: ImageViewLoadingController {
        get {
            if let loader = objc_getAssociatedObject(self, &AssociatedKeys.LoadingController) as? ImageViewLoadingController {
                return loader
            }
            let loader = ImageViewLoadingController { [weak self] in
                self?.nk_imageTask($0, didFinishWithResponse: $1, options: $2)
            }
            self.nk_imageLoadingController = loader
            return loader
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.LoadingController, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

private struct AssociatedKeys {
    static var LoadingController = "nk_imageViewLoadingController"
}
