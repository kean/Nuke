// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

#if !os(macOS)
import UIKit.UIImage
#else
import AppKit.NSImage
#endif

// MARK: - ImageResponse

/// Represents a response of a particular image task.
public struct ImageResponse {
    public let container: ImageContainer
    /// A convenience computed property which returns an image from the container.
    public var image: PlatformImage { container.image }
    public let urlResponse: URLResponse?
    /// Contains a cache type in case the image was returned from one of the
    /// pipeline caches (not including any of the HTTP caches if enabled).
    public let cacheType: CacheType?

    public init(container: ImageContainer, urlResponse: URLResponse? = nil, cacheType: CacheType? = nil) {
        self.container = container
        self.urlResponse = urlResponse
        self.cacheType = cacheType
    }

    func map(_ transformation: (ImageContainer) -> ImageContainer?) -> ImageResponse? {
        return autoreleasepool {
            guard let output = transformation(container) else {
                return nil
            }
            return ImageResponse(container: output, urlResponse: urlResponse, cacheType: cacheType)
        }
    }

    public enum CacheType {
        case memory
        case disk
    }
}

// MARK: - ImageContainer

public struct ImageContainer {
    public var image: PlatformImage
    public var type: ImageType?
    /// Returns `true` if the image in the container is a preview of the image.
    public var isPreview: Bool
    /// Contains the original image `data`, but only if the decoder decides to
    /// attach it to the image.
    ///
    /// The default decoder (`ImageDecoders.Default`) attaches data to GIFs to
    /// allow to display them using a rendering engine of your choice.
    ///
    /// - note: The `data`, along with the image container itself gets stored in the memory
    /// cache.
    public var data: Data?
    public var userInfo: [UserInfoKey: Any]

    public init(image: PlatformImage, type: ImageType? = nil, isPreview: Bool = false, data: Data? = nil, userInfo: [UserInfoKey: Any] = [:]) {
        self.image = image
        self.type = type
        self.isPreview = isPreview
        self.data = data
        self.userInfo = userInfo
    }

    /// Modifies the wrapped image and keeps all of the rest of the metadata.
    public func map(_ closure: (PlatformImage) -> PlatformImage?) -> ImageContainer? {
        guard let image = closure(self.image) else {
            return nil
        }
        return ImageContainer(image: image, type: type, isPreview: isPreview, data: data, userInfo: userInfo)
    }

    /// A key use in `userInfo`.
    public struct UserInfoKey: Hashable, ExpressibleByStringLiteral {
        public let rawValue: String

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.rawValue = value
        }

        /// A user info key to get the scan number (Int).
        public static let scanNumberKey: UserInfoKey = "github.com/kean/nuke/scan-number"
    }
}
