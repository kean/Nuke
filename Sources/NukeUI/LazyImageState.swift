// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import SwiftUI
import Combine

/// Describes current image state.
public struct LazyImageState {
    /// Returns the current fetch result.
    public let result: Result<ImageResponse, Error>?

    /// Returns a current error.
    public var error: Error? {
        if case .failure(let error) = result {
            return error
        }
        return nil
    }

    /// Returns an image view.
    @MainActor
    public var image: Image? {
#if os(macOS)
        imageContainer.map { Image(nsImage: $0.image) }
#else
        imageContainer.map { Image(uiImage: $0.image) }
#endif
    }

    /// Returns the fetched image.
    ///
    /// - note: In case pipeline has `isProgressiveDecodingEnabled` option enabled
    /// and the image being downloaded supports progressive decoding, the `image`
    /// might be updated multiple times during the download.
    public let imageContainer: ImageContainer?

    /// Returns `true` if the image is being loaded.
    public let isLoading: Bool

    /// The progress of the image download.
    public let progress: FetchImage.Progress?

    @MainActor
    init(_ fetchImage: FetchImage) {
        self.result = fetchImage.result
        self.imageContainer = fetchImage.imageContainer
        self.isLoading = fetchImage.isLoading
        self.progress = fetchImage.progress
    }
}
