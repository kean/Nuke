// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Combine
import Nuke
import SwiftUI

// MARK: - Deprecated in Nuke 14

extension FetchImage {
    @available(*, deprecated, message: "Renamed to `ImageTask.Progress`, which `FetchImage/progress` now returns. It's a struct, so a view that observed it with `@ObservedObject` now reads the value directly.")
    public typealias Progress = ImageTask.Progress
}

#if !os(watchOS)
extension LazyImageView {
    /// - warning: Deprecated in Nuke 14.0. Use ``isProgressiveRenderingEnabled`` instead.
    @available(*, deprecated, renamed: "isProgressiveRenderingEnabled", message: "Deprecated in Nuke 14.0. Use `isProgressiveRenderingEnabled` instead.")
    public var isProgressiveImageRenderingEnabled: Bool {
        get { isProgressiveRenderingEnabled }
        set { isProgressiveRenderingEnabled = newValue }
    }
}
#endif

// MARK: - Removed in Nuke 14
//
// Removed APIs are kept as unavailable stubs that name their replacement: the
// message goes straight into the compiler error. They are deleted two major
// versions after the removal.

extension FetchImage {
    @available(*, unavailable, message: "Removed in Nuke 14. Use `load(_:)` with an async closure, for example `load { try await pipeline.image(for: url) }`.")
    public func load<P: Publisher>(_ publisher: P) where P.Output == ImageResponse {
        fatalError("Removed in Nuke 14")
    }
}

// MARK: - Removed in Nuke 12 and 13
//
// For the code people and models remember, not for migrations. See the same section
// in `Sources/Nuke/Pipeline/Deprecated.swift`. These have no removal date.

@available(*, unavailable, message: "Removed in Nuke 12. `LazyImage` sizes itself the way `AsyncImage` does: resize the image in the `content` closure, for example `LazyImage(url: url) { $0.image?.resizable().aspectRatio(contentMode: .fill) }`.")
public enum ImageResizingMode {
    case fill, aspectFill, aspectFit, center, top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight
}

extension LazyImage {
    @available(*, unavailable, message: "Removed in Nuke 12. Use `LazyImage(url:)` or `LazyImage(request:)`.")
    public init(source: Any?) where Content == Image {
        fatalError("Removed in Nuke 12")
    }

    @available(*, unavailable, message: "Removed in Nuke 12. Use `LazyImage(url:content:)` or `LazyImage(request:content:)`.")
    public init(source: Any?, @ViewBuilder content: @escaping (LazyImageState) -> Content) {
        fatalError("Removed in Nuke 12")
    }

    @available(*, unavailable, message: "Removed in Nuke 12. `LazyImage` sizes itself the way `AsyncImage` does: resize the image in the `content` closure, for example `LazyImage(url: url) { $0.image?.resizable().aspectRatio(contentMode: .fill) }`.")
    public init(url: URL?, resizingMode: ImageResizingMode) where Content == Image {
        fatalError("Removed in Nuke 12")
    }

    @available(*, unavailable, message: "Removed in Nuke 12. `LazyImage` sizes itself the way `AsyncImage` does: resize the image in the `content` closure, for example `LazyImage(request: request) { $0.image?.resizable().aspectRatio(contentMode: .fill) }`.")
    public init(request: ImageRequest?, resizingMode: ImageResizingMode) where Content == Image {
        fatalError("Removed in Nuke 12")
    }

    @available(*, unavailable, message: "Removed in Nuke 12. Use `onCompletion(_:)`.")
    public func onSuccess(_ closure: @escaping @MainActor @Sendable (ImageResponse) -> Void) -> Self {
        fatalError("Removed in Nuke 12")
    }

    @available(*, unavailable, message: "Removed in Nuke 12. Use `onCompletion(_:)`.")
    public func onFailure(_ closure: @escaping @MainActor @Sendable (ImagePipeline.Error) -> Void) -> Self {
        fatalError("Removed in Nuke 12")
    }

    @available(*, unavailable, message: "Removed in Nuke 12. Read `state.progress` in the `content` closure.")
    public func onProgress(_ closure: @escaping @MainActor @Sendable (ImageTask.Progress) -> Void) -> Self {
        fatalError("Removed in Nuke 12")
    }

    @available(*, unavailable, message: "Removed in Nuke 12. Read `state.imageContainer?.isPreview` in the `content` closure.")
    public func onPreview(_ closure: @escaping @MainActor @Sendable (ImageResponse) -> Void) -> Self {
        fatalError("Removed in Nuke 12")
    }
}
