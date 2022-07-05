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
    var onVideoFinished: (() -> Void)?
    var restartVideo: Bool = false

    public init(_ image: NSImage) {
        self.init(ImageContainer(image: image))
    }

    public init(_ imageContainer: ImageContainer, onCreated: ((ImageView) -> Void)? = nil) {
        self.imageContainer = imageContainer
        self.onCreated = onCreated
    }

    public func makeNSView(context: Context) -> ImageView {
        let view = ImageView()
        view.videoPlayerView.onVideoFinished = onVideoFinished
        onCreated?(view)
        return view
    }

    public func updateNSView(_ imageView: ImageView, context: Context) {
        if restartVideo {
            imageView.videoPlayerView.restart()
        }
        guard imageView.imageContainer?.image !== imageContainer.image else { return }
        imageView.imageContainer = imageContainer
    }
}
#elseif os(iOS) || os(tvOS)
/// Displays images. Supports animated images and video playback.
@MainActor
public struct Image: UIViewRepresentable {
    let imageContainer: ImageContainer
    let onCreated: ((ImageView) -> Void)?
    var resizingMode: ImageResizingMode?
    var onVideoFinished: (() -> Void)?
    var restartVideo: Bool = false

    public init(_ image: UIImage) {
        self.init(ImageContainer(image: image))
    }

    public init(_ imageContainer: ImageContainer, onCreated: ((ImageView) -> Void)? = nil) {
        self.imageContainer = imageContainer
        self.onCreated = onCreated
    }

    public func makeUIView(context: Context) -> ImageView {
        let imageView = ImageView()
        if let resizingMode = self.resizingMode {
            imageView.resizingMode = resizingMode
        }
        imageView.videoPlayerView.onVideoFinished = onVideoFinished
        onCreated?(imageView)
        return imageView
    }

    public func updateUIView(_ imageView: ImageView, context: Context) {
        if restartVideo {
            imageView.videoPlayerView.restart()
        }
        guard imageView.imageContainer?.image !== imageContainer.image else { return }
        imageView.imageContainer = imageContainer
    }

    /// Sets the resizing mode for the image.
    public func resizingMode(_ mode: ImageResizingMode) -> Self {
        var copy = self
        copy.resizingMode = mode
        return copy
    }
}
#endif

#if os(macOS) || os(iOS) || os(tvOS)
extension Image {
    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Deprecated. Please use the underlying video player view directly or create a custom wrapper for it. More APIs coming in future versions.")
    public func onVideoFinished(content: @escaping () -> Void) -> Self {
        var copy = self
        copy.onVideoFinished = content
        return copy
    }

    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Deprecated. Please use the underlying video player view directly or create a custom wrapper for it. More APIs coming in future versions.")
    public func restartVideo(_ value: Bool) -> Self {
        var copy = self
        copy.restartVideo = value
        return copy
    }
}
#endif
