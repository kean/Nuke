// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation
import SwiftUI
import Nuke

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

@available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 10.16, *)
extension LazyImage {
#if !os(macOS)
    @available(*, deprecated, message: "The resizingMode is no longer supported. Please use one of the initializers that allows you to customize the displayed image directly.")
    public init(url: URL?, resizingMode: ImageResizingMode) where Content == Image {
        self.init(request: url.map { ImageRequest(url: $0) }, resizingMode: resizingMode)
    }

    @available(*, deprecated, message: "The resizingMode is no longer supported. Please use one of the initializers that allows you to customize the displayed image directly.")
    public init(request: ImageRequest?, resizingMode: ImageResizingMode) where Content == Image {
        self.init(request: request)
    }
#endif

    @available(*, deprecated, message: "This callback no longer gets called. Please create a custom view and use ``FetchImage`` directly to set these callbacks")
    public func onStart(_ closure: @escaping (ImageTask) -> Void) -> Self { self }

    @available(*, deprecated, message: "This callback no longer gets called. Please create a custom view and use ``FetchImage`` directly to set these callbacks")
    public func onPreview(_ closure: @escaping (ImageResponse) -> Void) -> Self { self }

    @available(*, deprecated, message: "This callback no longer gets called. Please create a custom view and use ``FetchImage`` directly to set these callbacks")
    public func onProgress(_ closure: @escaping (ImageTask.Progress) -> Void) -> Self { self }

    @available(*, deprecated, message: "This callback no longer gets called. Please create a custom view and use ``FetchImage`` directly to set these callbacks")
    public func onSuccess(_ closure: @escaping (ImageResponse) -> Void) -> Self { self }

    @available(*, deprecated, message: "This callback no longer gets called. Please create a custom view and use ``FetchImage`` directly to set these callbacks")
    public func onFailure(_ closure: @escaping (Error) -> Void) -> Self { self }

    @available(*, deprecated, message: "This callback no longer gets called. Please create a custom view and use ``FetchImage`` directly to set these callbacks")
    public func onCompletion(_ closure: @escaping (Result<ImageResponse, Error>) -> Void) -> Self { self }

#if !os(watchOS)
    @available(*, deprecated, message: "ImageView is deprecated starting with version 12.0")
    public func onCreated(_ configure: ((ImageView) -> Void)?) -> Self { self }
#endif
}

#if os(macOS)
@available(*, deprecated, message: "ImageView was removed in version 12.0 and is no longer supported.")
@MainActor public class ImageView: NSImageView {}

@available(*, deprecated, message: "VideoPlayerView was removed in version 12.0 and is no longer supported. You can use the following snippet https://gist.github.com/kean/fd1df0e1345f787552497095eb84d252.")
@MainActor public class VideoPlayerView: UIImageView {}
#elseif !os(watchOS)
@available(*, deprecated, message: "ImageView was removed in version 12.0 and is no longer supported.")
@MainActor public class ImageView: UIImageView {}

@available(*, deprecated, message: "VideoPlayerView was removed in version 12.0 and is no longer supported. You can use the following snippet https://gist.github.com/kean/fd1df0e1345f787552497095eb84d252.")
@MainActor public class VideoPlayerView: UIImageView {}
#endif

@available(*, deprecated, message: "The resizingMode is no longer supported. Please use one of the initializers that allows you to customize the displayed image directly.")
public enum ImageResizingMode {
    case fill
    case aspectFit
    case aspectFill
    case center
    case top
    case bottom
    case left
    case right
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}
