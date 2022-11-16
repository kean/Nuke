// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
/// Displays images. Supports animated images and video playback.
@MainActor
public struct Image: NSViewRepresentable {
    let imageContainer: ImageContainer
    let onCreated: ((ImageView) -> Void)?
    var isAnimatedImageRenderingEnabled: Bool?
    var isVideoRenderingEnabled: Bool?
    var isVideoLooping: Bool?
    var resizingMode: ImageResizingMode?

    public init(_ image: NSImage) {
        self.init(ImageContainer(image: image))
    }

    public init(_ imageContainer: ImageContainer, onCreated: ((ImageView) -> Void)? = nil) {
        self.imageContainer = imageContainer
        self.onCreated = onCreated
    }

    public func makeNSView(context: Context) -> ImageView {
        let view = ImageView()
        onCreated?(view)
        return view
    }

    public func updateNSView(_ imageView: ImageView, context: Context) {
        updateImageView(imageView)
    }
}
#elseif os(iOS) || os(tvOS)
/// Displays images. Supports animated images and video playback.
@MainActor
public struct Image: UIViewRepresentable {
    let imageContainer: ImageContainer
    let onCreated: ((ImageView) -> Void)?
    var isAnimatedImageRenderingEnabled: Bool?
    var isVideoRenderingEnabled: Bool?
    var isVideoFrameAnimationEnabled: Bool?
    var isVideoLooping: Bool?
    var resizingMode: ImageResizingMode?

    public init(_ image: UIImage) {
        self.init(ImageContainer(image: image))
    }

    public init(_ imageContainer: ImageContainer, onCreated: ((ImageView) -> Void)? = nil) {
        self.imageContainer = imageContainer
        self.onCreated = onCreated
    }

    public func makeUIView(context: Context) -> ImageView {
        let imageView = ImageView()
        onCreated?(imageView)
        return imageView
    }

    public func updateUIView(_ imageView: ImageView, context: Context) {
        updateImageView(imageView)
    }
}
#endif

#if os(macOS) || os(iOS) || os(tvOS)
extension Image {
    func updateImageView(_ imageView: ImageView) {
        if imageView.imageContainer?.image !== imageContainer.image {
            imageView.imageContainer = imageContainer
        }
        if let value = resizingMode { imageView.resizingMode = value }
        if let value = isVideoRenderingEnabled { imageView.isVideoRenderingEnabled = value }
        if let value = isVideoFrameAnimationEnabled { imageView.isVideoFrameAnimationEnabled = value }
        if let value = isAnimatedImageRenderingEnabled { imageView.isAnimatedImageRenderingEnabled = value }
        if let value = isVideoLooping { imageView.isVideoLooping = value }
    }

    /// Sets the resizing mode for the image.
    public func resizingMode(_ mode: ImageResizingMode) -> Self {
        var copy = self
        copy.resizingMode = mode
        return copy
    }

    public func videoRenderingEnabled(_ isEnabled: Bool) -> Self {
        var copy = self
        copy.isVideoRenderingEnabled = isEnabled
        return copy
    }

    public func videoLoopingEnabled(_ isEnabled: Bool) -> Self {
        var copy = self
        copy.isVideoLooping = isEnabled
        return copy
    }

    public func videoFrameAnimationEnabled(_ isEnabled: Bool) -> Self {
        var copy = self
        copy.isVideoFrameAnimationEnabled = isEnabled
        return copy
    }

    public func animatedImageRenderingEnabled(_ isEnabled: Bool) -> Self {
        var copy = self
        copy.isAnimatedImageRenderingEnabled = isEnabled
        return copy
    }
}
#endif
