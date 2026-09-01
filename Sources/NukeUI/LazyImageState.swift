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
    var progress: ImageTask.Progress { get }

    /// Returns the fetched image as an animation, if it is one.
    ///
    /// Pass it to ``AnimatedImage`` to play it. The value is `nil` for every
    /// image that isn't animated, which is the signal to display ``image``.
    var animatedImage: AnimatedImageSource? { get }
}

extension LazyImageState {
    /// The animation the pipeline parsed while it decoded the image.
    public var animatedImage: AnimatedImageSource? {
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
