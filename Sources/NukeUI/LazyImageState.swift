// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

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
        return imageContainer.map { Image($0, isVideoRenderingEnabled: isVideoRenderingEnabled) }
#elseif os(watchOS)
        return imageContainer.map { Image(uiImage: $0.image, isVideoRenderingEnabled: isVideoRenderingEnabled) }
#else
        return imageContainer.map { Image($0, isVideoRenderingEnabled: isVideoRenderingEnabled) }
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
    public let progress: ImageTask.Progress

	private let isVideoRenderingEnabled: Bool

    @MainActor
	init(_ fetchImage: FetchImage, isVideoRenderingEnabled: Bool) {
        self.result = fetchImage.result
        self.imageContainer = fetchImage.imageContainer
        self.isLoading = fetchImage.isLoading
        self.progress = fetchImage.progress
		self.isVideoRenderingEnabled = isVideoRenderingEnabled
    }
}
