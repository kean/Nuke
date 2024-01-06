// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

#if !os(watchOS)
import AVKit
#endif

import Foundation

#if !os(macOS)
import UIKit.UIImage
/// Alias for `UIImage`.
public typealias PlatformImage = UIImage
#else
import AppKit.NSImage
/// Alias for `NSImage`.
public typealias PlatformImage = NSImage
#endif

/// An image container with an image and associated metadata.
public struct ImageContainer: @unchecked Sendable {
#if os(macOS)
    /// A fetched image.
    public var image: NSImage {
        get { ref.image }
        set { mutate { $0.image = newValue } }
    }
#else
    /// A fetched image.
    public var image: UIImage {
        get { ref.image }
        set { mutate { $0.image = newValue } }
    }
#endif

    /// An image type.
    public var type: AssetType? {
        get { ref.type }
        set { mutate { $0.type = newValue } }
    }

    /// Returns `true` if the image in the container is a preview of the image.
    public var isPreview: Bool {
        get { ref.isPreview }
        set { mutate { $0.isPreview = newValue } }
    }

    /// Contains the original image `data`, but only if the decoder decides to
    /// attach it to the image.
    ///
    /// The default decoder (``ImageDecoders/Default``) attaches data to GIFs to
    /// allow to display them using a rendering engine of your choice.
    ///
    /// - note: The `data`, along with the image container itself gets stored
    /// in the memory cache.
    public var data: Data? {
        get { ref.data }
        set { mutate { $0.data = newValue } }
    }

    /// An metadata provided by the user.
    public var userInfo: [UserInfoKey: Any] {
        get { ref.userInfo }
        set { mutate { $0.userInfo = newValue } }
    }

    private var ref: Container

    /// Initializes the container with the given image.
    public init(image: PlatformImage, type: AssetType? = nil, isPreview: Bool = false, data: Data? = nil, userInfo: [UserInfoKey: Any] = [:]) {
        self.ref = Container(image: image, type: type, isPreview: isPreview, data: data, userInfo: userInfo)
    }

    func map(_ closure: (PlatformImage) throws -> PlatformImage) rethrows -> ImageContainer {
        var copy = self
        copy.image = try closure(image)
        return copy
    }

    /// A key use in ``userInfo``.
    public struct UserInfoKey: Hashable, ExpressibleByStringLiteral, Sendable {
        public let rawValue: String

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.rawValue = value
        }

        // For internal purposes.
        static let isThumbnailKey: UserInfoKey = "com.github/kean/nuke/skip-decompression"

        /// A user info key to get the scan number (Int).
        public static let scanNumberKey: UserInfoKey = "com.github/kean/nuke/scan-number"
    }

    // MARK: - Copy-on-Write

    private mutating func mutate(_ closure: (Container) -> Void) {
        if !isKnownUniquelyReferenced(&ref) {
            ref = Container(ref)
        }
        closure(ref)
    }

    private final class Container: @unchecked Sendable {
        var image: PlatformImage
        var type: AssetType?
        var isPreview: Bool
        var data: Data?
        var userInfo: [UserInfoKey: Any]

        init(image: PlatformImage, type: AssetType?, isPreview: Bool, data: Data? = nil, userInfo: [UserInfoKey: Any]) {
            self.image = image
            self.type = type
            self.isPreview = isPreview
            self.data = data
            self.userInfo = userInfo
        }

        init(_ ref: Container) {
            self.image = ref.image
            self.type = ref.type
            self.isPreview = ref.isPreview
            self.data = ref.data
            self.userInfo = ref.userInfo
        }
    }
}
