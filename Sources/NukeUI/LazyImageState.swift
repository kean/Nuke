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

    /// Loads the image again, typically to retry after a failure:
    ///
    /// ```swift
    /// LazyImage(url: url) { state in
    ///     if let image = state.image {
    ///         image
    ///     } else if state.error != nil {
    ///         Button("Retry") { state.reload() }
    ///     }
    /// }
    /// ```
    ///
    /// A load that is still running keeps running. If the memory cache has the
    /// image, it is what gets displayed. To skip the caches, load a request with
    /// ``ImageRequest/Options-swift.struct/reloadIgnoringCachedData``.
    func reload()
}

extension LazyImageState {
    /// Does nothing by default: there is nothing to load again in a state that
    /// isn't backed by a load, such as one made for a preview.
    public func reload() {}

    /// Returns the fetched image as an animation, if it is one.
    ///
    /// Pass it to ``AnimatedImage`` to play it. The value is `nil` for every
    /// image that isn't animated, which is the signal to display ``image``.
    public var animation: AnimatedImageSource? {
        imageContainer?.animation
    }

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
