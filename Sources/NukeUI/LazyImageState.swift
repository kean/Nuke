// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import SwiftUI

/// Describes the current image state.
@MainActor
public protocol LazyImageState {
    /// Returns the current fetch result.
    var result: Result<ImageResponse, ImagePipeline.Error>? { get }

    /// Returns the fetched image.
    ///
    /// - note: In case the pipeline has the `isProgressiveDecodingEnabled` option enabled
    /// and the image being downloaded supports progressive decoding, the `image`
    /// might be updated multiple times during the download.
    var imageContainer: ImageContainer? { get }

    /// Returns `true` if the image is being loaded.
    var isLoading: Bool { get }

    /// The progress of the image download.
    ///
    /// Returns `ImageTask.Progress`, the same struct the pipeline reports.
    /// `NukeUI` no longer has a progress type of its own: `FetchImage.Progress`
    /// is a deprecated typealias for it.
    var progress: ImageTask.Progress { get }

    /// Loads the image again. Use it to let people retry a load that failed:
    ///
    /// ```swift
    /// LazyImage(url: url) { state in
    ///     if let image = state.image {
    ///         image
    ///     } else if state.error != nil {
    ///         Button("Try Again") { state.reload() }
    ///     } else {
    ///         ProgressView()
    ///     }
    /// }
    /// ```
    ///
    /// To retry automatically before showing an error, set a
    /// ``ImagePipeline/RetryPolicy`` on the pipeline or the request.
    func reload()
}

extension LazyImageState {
    /// Returns the fetched image as an animation, if it is one.
    ///
    /// Pass it to ``AnimatedImage`` to play it. The value is `nil` for every
    /// image that isn't animated, which is the signal to display ``image``.
    public var animation: AnimatedImageSource? {
        imageContainer?.animation
    }

    /// Does nothing, for the states that aren't backed by a ``FetchImage``.
    public func reload() {}

    /// Returns the current error.
    public var error: ImagePipeline.Error? {
        if case .failure(let error) = result {
            return error
        }
        return nil
    }

    /// Returns an image view.
    public var image: Image? {
        guard let imageContainer else { return nil }
#if os(macOS)
        return Image(nsImage: imageContainer.image)
#else
        return Image(uiImage: imageContainer.image)
#endif
    }
}

extension FetchImage: LazyImageState {}
