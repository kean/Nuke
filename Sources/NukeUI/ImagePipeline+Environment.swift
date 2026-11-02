// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI
import Nuke

extension EnvironmentValues {
    /// The pipeline that ``LazyImage`` loads images with.
    ///
    /// Set it with ``SwiftUICore/View/imagePipeline(_:)``. Unless a pipeline is
    /// set, this is ``ImagePipeline/shared``, read at the time the image is
    /// loaded: assigning a new ``ImagePipeline/shared`` after a view is created
    /// still applies to it.
    public var imagePipeline: ImagePipeline {
        get { optionalImagePipeline ?? .shared }
        set { optionalImagePipeline = newValue }
    }

    // The key is optional so that its default isn't `ImagePipeline.shared`.
    // A default is evaluated once, and `shared` can be assigned at any time.
    // `LazyImage` reads this one, and falls back to `shared` when it loads.
    var optionalImagePipeline: ImagePipeline? {
        get { self[ImagePipelineKey.self] }
        set { self[ImagePipelineKey.self] = newValue }
    }
}

private struct ImagePipelineKey: EnvironmentKey {
    static let defaultValue: ImagePipeline? = nil
}

extension View {
    /// Sets the pipeline that ``LazyImage`` views in this view hierarchy load
    /// images with, the way `asyncImageURLSession(_:)` sets the session of
    /// `AsyncImage`.
    ///
    /// ```swift
    /// ContentView()
    ///     .imagePipeline(thumbnailPipeline)
    /// ```
    ///
    /// A pipeline set on the view itself with ``LazyImage/pipeline(_:)`` takes
    /// precedence. Changing the pipeline reloads the images that are displayed.
    public func imagePipeline(_ pipeline: ImagePipeline) -> some View {
        environment(\.optionalImagePipeline, pipeline)
    }
}
