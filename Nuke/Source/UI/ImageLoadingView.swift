// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import UIKit

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
    func nk_setImageWithURL(URL: NSURL) -> ImageTask
    func nk_setImageWithRequest(request: ImageRequest, options: ImageViewLoadingOptions?) -> ImageTask
}

public extension ImageLoadingView where Self: UIView {
    public func nk_setImageWithURL(URL: NSURL) -> ImageTask {
        return self.nk_setImageWithRequest(ImageRequest(URL: URL, targetSize: self.nk_targetSize(), contentMode: .AspectFill))
    }
    
    func nk_setImageWithRequest(request: ImageRequest) -> ImageTask {
        return self.nk_setImageWithRequest(request, options: nil)
    }
}

public extension UIView {
    public func nk_targetSize() -> CGSize {
        let size = self.bounds.size
        let scale = UIScreen.mainScreen().scale
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

// MARK: - ImageDisplayingView

/** View that supports displaying loaded images.
*/
public protocol ImageDisplayingView: class {
    var nk_displayedImage: Image? { get set }
    func nk_imageTask(task: ImageTask, didFinishWithResponse response: ImageResponse, options: ImageViewLoadingOptions?)
}

public var ImageViewDefaultAnimationDuration = 0.25

public extension ImageDisplayingView where Self: UIView {
    /** Note that classes cannot be overridden declarations from extensions. It means that if you have a class (like UIImageView) that implements ImageDisplayingView protocol in an extension you won't be able to override this method in a subclass of UIImageView. But you can override it in an extenstion of the subclass.
    */
    public func nk_imageTask(task: ImageTask, didFinishWithResponse response: ImageResponse, options: ImageViewLoadingOptions?) {
        switch response {
        case let .Success(image, info):
            let previousImage = self.nk_displayedImage
            self.nk_displayedImage = image
            guard !info.fastResponse else {
                return
            }
            if let animations = options?.animations {
                animations(self)
            } else {
                if previousImage == nil {
                    self.alpha = 0.0
                    UIView.animateWithDuration(ImageViewDefaultAnimationDuration) {
                        self.alpha = 1.0
                    }
                } else {
                    UIView.transitionWithView(self, duration: ImageViewDefaultAnimationDuration, options: UIViewAnimationOptions.TransitionCrossDissolve, animations: nil, completion: nil)
                }
            }
        default: return
        }
    }
}

// MARK: - Default ImageLoadingView Implementation

/** Default ImageLoadingView implementation for each UIView that implements ImageDisplayingView protocol.
*/
public extension ImageLoadingView where Self: ImageDisplayingView {
    
    // MARK: ImageLoadingView
    
    public func nk_cancelLoading() {
        self.nk_imageLoadingController.cancelLoading()
    }
    
    public func nk_setImageWithRequest(request: ImageRequest, options: ImageViewLoadingOptions?) -> ImageTask {
        if let placeholder = options?.placeholder {
            self.nk_displayedImage = placeholder
        }
        return self.nk_imageLoadingController.setImageWithRequest(request, options: options)
    }
    
    // MARK: Extensions
    
    public func nk_prepareForReuse() {
        self.nk_displayedImage = nil
        self.nk_cancelLoading()
    }
    
    // MARK: Helpers
    
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
    static var LoadingController = "nk_ImageViewLoadingController"
}
