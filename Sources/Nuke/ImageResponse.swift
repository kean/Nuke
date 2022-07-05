// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

#if !os(macOS)
import UIKit.UIImage
#else
import AppKit.NSImage
#endif

/// An image response that contains a fetched image and some metadata.
public struct ImageResponse: @unchecked Sendable {
    /// An image container with an image and associated metadata.
    public var container: ImageContainer

    #if os(macOS)
    /// A convenience computed property that returns an image from the container.
    public var image: NSImage { container.image }
    #else
    /// A convenience computed property that returns an image from the container.
    public var image: UIImage { container.image }
    #endif

    /// Returns `true` if the image in the container is a preview of the image.
    public var isPreview: Bool { container.isPreview }

    /// The request for which the response was created.
    public var request: ImageRequest

    /// A response. `nil` unless the resource was fetched from the network or an
    /// HTTP cache.
    public var urlResponse: URLResponse?

    /// Contains a cache type in case the image was returned from one of the
    /// pipeline caches (not including any of the HTTP caches if enabled).
    public var cacheType: CacheType?

    /// Initializes the response with the given image.
    public init(container: ImageContainer, request: ImageRequest, urlResponse: URLResponse? = nil, cacheType: CacheType? = nil) {
        self.container = container
        self.request = request
        self.urlResponse = urlResponse
        self.cacheType = cacheType
    }

    /// A cache type.
    public enum CacheType: Sendable {
        /// Memory cache (see ``ImageCaching``)
        case memory
        /// Disk cache (see ``DataCaching``)
        case disk
    }

    func map(_ transform: (ImageContainer) throws -> ImageContainer) rethrows -> ImageResponse {
        var response = self
        response.container = try transform(response.container)
        return response
    }
}
