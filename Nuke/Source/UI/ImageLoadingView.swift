// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

#if os(OSX)
    import Cocoa
    public typealias View = NSView
#else
    import UIKit
    public typealias View = UIView
#endif

// MARK: - ImageLoadingView

public struct ImageViewLoadingOptions {
    public var placeholder: Image?
    public var animations: ((ImageDisplayingView) -> Void)?
    public init(placeholder: Image? = nil, animations: ((ImageDisplayingView) -> Void)? = nil) {
        self.placeholder = placeholder
        self.animations = animations
    }
}

/** View that supports image loading.
*/
public protocol ImageLoadingView: class {
    func nk_cancelLoading()
    
    /** Loads and displays an image for the given URL. Cancels previously stared requests.
     
     Default implementation uses ImageContentMode.AspectFill, and current view size multiplied by screen scaling factor as an image target size.
    */
    func nk_setImageWithURL(URL: NSURL) -> ImageTask
    
    /** Loads and displays an image for the given request. Cancels previously stared requests.
    */
    func nk_setImageWithRequest(request: ImageRequest, options: ImageViewLoadingOptions?) -> ImageTask
}

public extension ImageLoadingView where Self: View {
    public func nk_setImageWithURL(URL: NSURL) -> ImageTask {
        return self.nk_setImageWithRequest(ImageRequest(URL: URL, targetSize: self.nk_targetSize(), contentMode: .AspectFill))
    }
    
    func nk_setImageWithRequest(request: ImageRequest) -> ImageTask {
        return self.nk_setImageWithRequest(request, options: nil)
    }
}

public extension View {
    /** Returns image target size in pixels for the view. Target size is calculated by multiplying view's size by screen scaling factor.
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

/** View that supports displaying loaded images.

See https://github.com/kean/Nuke/issues/38 for more info about overriding those methods.
*/
public protocol ImageDisplayingView: class {
    var nk_image: Image? { get set }
    func nk_imageTask(task: ImageTask, didFinishWithResponse response: ImageResponse, options: ImageViewLoadingOptions?)
}

public var ImageViewDefaultAnimationDuration = 0.25

public extension ImageDisplayingView where Self: View {
    public func nk_imageTask(task: ImageTask, didFinishWithResponse response: ImageResponse, options: ImageViewLoadingOptions?) {
        switch response {
        case let .Success(image, info):
            let previousImage = self.nk_image
            self.nk_image = image
            guard !info.fastResponse else {
                return
            }
            if let animations = options?.animations {
                animations(self)
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

/** Default ImageLoadingView implementation for each view that implements ImageDisplayingView protocol.
*/
public extension ImageLoadingView where Self: ImageDisplayingView {
    
    // MARK: ImageLoadingView
    
    public func nk_cancelLoading() {
        self.nk_imageLoadingController.cancelLoading()
    }
    
    public func nk_setImageWithRequest(request: ImageRequest, options: ImageViewLoadingOptions?) -> ImageTask {
        if let placeholder = options?.placeholder {
            self.nk_image = placeholder
        }
        return self.nk_imageLoadingController.setImageWithRequest(request, options: options)
    }
    
    // MARK: Extensions
    
    /** Removes currently displayed image and cancels image loading.
    */
    public func nk_prepareForReuse() {
        self.nk_image = nil
        self.nk_cancelLoading()
    }
    
    // MARK: Helpers
    
    /** Returns current image task.
    */
    public var nk_imageTask: ImageTask? {
        return self.nk_imageLoadingController.imageTask
    }
    
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
