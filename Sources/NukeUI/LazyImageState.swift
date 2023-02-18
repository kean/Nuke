// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import SwiftUI
import Combine

/// Describes current image state.
@MainActor
public struct LazyImageState {
    let viewModel: FetchImage

    /// Returns the current fetch result.
    public var result: Result<ImageResponse, Error>? { viewModel.result }

    /// Returns the current error.
    public var error: Error? {
        if case .failure(let error) = result {
            return error
        }
        return nil
    }

    /// Returns an image view.
    public var image: Image? { viewModel.image }

    /// Returns the fetched image.
    ///
    /// - note: In case pipeline has `isProgressiveDecodingEnabled` option enabled
    /// and the image being downloaded supports progressive decoding, the `image`
    /// might be updated multiple times during the download.
    public var imageContainer: ImageContainer? { viewModel.imageContainer }

    /// Returns `true` if the image is being loaded.
    public var isLoading: Bool { viewModel.isLoading }

    /// The progress of the image download.
    public var progress: FetchImage.Progress { viewModel.progress }
}
