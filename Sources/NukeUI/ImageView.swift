// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

#if !os(watchOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if (os(iOS) || os(tvOS)) && !targetEnvironment(macCatalyst)
import Gifu

public typealias AnimatedImageView = Gifu.GIFImageView
#endif

/// Lazily loads and displays images.
public class ImageView: _PlatformBaseView {

    // MARK: Underlying Views

#if os(macOS)
    /// Returns an underlying image view.
    public let imageView = NSImageView()
#else
    /// Returns an underlying image view.
    public let imageView = UIImageView()
#endif

#if os(iOS) || os(tvOS)
    /// Sets the content mode for all container views.
    public var resizingMode: ImageResizingMode = .aspectFill {
        didSet {
            imageView.contentMode = .init(resizingMode: resizingMode)
            #if !targetEnvironment(macCatalyst)
            _animatedImageView?.contentMode = .init(resizingMode: resizingMode)
            #endif
            _videoPlayerView?.videoGravity = .init(resizingMode)
        }
    }
#endif

#if (os(iOS) || os(tvOS)) && !targetEnvironment(macCatalyst)
    /// Returns an underlying animated image view used for rendering animated images.
    public var animatedImageView: AnimatedImageView {
        if let view = _animatedImageView {
            return view
        }
        let view = makeAnimatedImageView()
        addContentView(view)
        _animatedImageView = view
        return view
    }

    private func makeAnimatedImageView() -> AnimatedImageView {
        let view = AnimatedImageView()
        view.contentMode = .init(resizingMode: resizingMode)
        return view
    }

    private var _animatedImageView: AnimatedImageView?
#endif

    /// Returns an underlying video player view.
    public var videoPlayerView: VideoPlayerView {
        if let view = _videoPlayerView {
            return view
        }
        let view = makeVideoPlayerView()
        addContentView(view)
        _videoPlayerView = view
        return view
    }

    private func makeVideoPlayerView() -> VideoPlayerView {
        let view = VideoPlayerView()
#if os(macOS)
        view.videoGravity = .resizeAspect
#else
        view.videoGravity = .init(resizingMode)
#endif
        return view
    }

    private var _videoPlayerView: VideoPlayerView?

    public var customContentView: _PlatformBaseView? {
        get { _customContentView }
        set {
            _customContentView?.removeFromSuperview()
            _customContentView = newValue
            if let customView = _customContentView {
                addContentView(customView)
                customView.isHidden = false
            }
        }
    }
  
    private var _customContentView: _PlatformBaseView?

    /// `true` by default. If disabled, animated image rendering will be disabled.
    public var isAnimatedImageRenderingEnabled = true

    /// `true` by default. Set to `true` to enable video support.
    public var isVideoRenderingEnabled = true


    // MARK: Initializers

    public override init(frame: CGRect) {
        super.init(frame: frame)
        didInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        didInit()
    }

    private func didInit() {
        addContentView(imageView)

#if !os(macOS)
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
#else
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.animates = true // macOS supports animated images out of the box
#endif
    }

    /// Displays the given image.
    ///
    /// Supports platform images (`UIImage`) and `ImageContainer`. Use `ImageContainer`
    /// if you need to pass additional parameters alongside the image, like
    /// original image data for GIF rendering.
    public var imageContainer: ImageContainer? {
        get { _imageContainer }
        set {
            _imageContainer = newValue
            if let imageContainer = newValue {
                display(imageContainer)
            } else {
                reset()
            }
        }
    }
    var _imageContainer: ImageContainer?

    public var isVideoLooping: Bool {
        set {
            videoPlayerView.isLooping = newValue
        }
        get {
            videoPlayerView.isLooping
        }
    }
    var onVideoFinished: (() -> Void)?

    func restartVideo() {
        videoPlayerView.restart()
    }

#if os(macOS)
    public var image: NSImage? {
        get { imageContainer?.image }
        set { imageContainer = newValue.map { ImageContainer(image: $0) } }
    }
#else
    public var image: UIImage? {
        get { imageContainer?.image }
        set { imageContainer = newValue.map { ImageContainer(image: $0) } }
    }
#endif

    private func display(_ container: ImageContainer) {
        if let customView = makeCustomContentView(for: container) {
            customContentView = customView
            return
        }
#if (os(iOS) || os(tvOS)) && !targetEnvironment(macCatalyst)
        if isAnimatedImageRenderingEnabled, let data = container.data, container.type == .gif {
            animatedImageView.animate(withGIFData: data)
            animatedImageView.isHidden = false
            return
        }
#endif
        if isVideoRenderingEnabled, let asset = container.asset {
            videoPlayerView.isHidden = false
            videoPlayerView.asset = asset
            videoPlayerView.onVideoFinished = onVideoFinished
            videoPlayerView.play()
        } else {
            imageView.image = container.image
            imageView.isHidden = false
        }
    }

    private func makeCustomContentView(for container: ImageContainer) -> _PlatformBaseView? {
        for closure in ImageView.registersContentViews {
            if let view = closure(container) {
                return view
            }
        }
        return nil
    }

    /// Cancels current request and prepares the view for reuse.
    func reset() {
        _imageContainer = nil

        imageView.isHidden = true
        imageView.image = nil

#if (os(iOS) || os(tvOS)) && !targetEnvironment(macCatalyst)
        _animatedImageView?.isHidden = true
        _animatedImageView?.image = nil
#endif

        _videoPlayerView?.isHidden = true
        _videoPlayerView?.reset()

        _customContentView?.removeFromSuperview()
        _customContentView = nil
    }

    // MARK: Extending Rendering System

#if os(iOS) || os(tvOS)
    /// Registers a custom content view to be used for displaying the given image.
    ///
    /// - parameter closure: A closure to get called when the image needs to be
    /// displayed. The view gets added to the `contentView`. You can return `nil`
    /// if you want the default rendering to happen.
    public static func registerContentView(_ closure: @escaping (ImageContainer) -> UIView?) {
        registersContentViews.append(closure)
    }
#else
    /// Registers a custom content view to be used for displaying the given image.
    ///
    /// - parameter closure: A closure to get called when the image needs to be
    /// displayed. The view gets added to the `contentView`. You can return `nil`
    /// if you want the default rendering to happen.
    public static func registerContentView(_ closure: @escaping (ImageContainer) -> NSView?) {
        registersContentViews.append(closure)
    }
#endif

    public static func removeAllRegisteredContentViews() {
        registersContentViews.removeAll()
    }

    private static var registersContentViews: [(ImageContainer) -> _PlatformBaseView?] = []

    // MARK: Misc

    private func addContentView(_ view: _PlatformBaseView) {
        addSubview(view)
        view.pinToSuperview()
        view.isHidden = true
    }
}
#endif
