// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

#if !os(macOS)
import UIKit.UIImage
/// Alias for `UIImage`.
public typealias PlatformImage = UIImage
/// Alias for `UIColor`.
public typealias PlatformColor = UIColor
#else
import AppKit.NSImage
/// Alias for `NSImage`.
public typealias PlatformImage = NSImage
/// Alias for `NSColor`.
public typealias PlatformColor = NSColor
#endif

/// An image container with an image and associated metadata.
public struct ImageContainer: Sendable {
    /// The fetched image.
#if os(macOS)
    public var image: NSImage {
        get { ref.image }
        set { mutate { $0.image = newValue } }
    }
#else
    public var image: UIImage {
        get { ref.image }
        set { mutate { $0.image = newValue } }
    }
#endif

    /// The detected format of the image data, such as JPEG, PNG, or GIF.
    /// `nil` if the format is unknown or not relevant.
    public var type: AssetType? {
        get { ref.type }
        set { mutate { $0.type = newValue } }
    }

    /// Returns `true` if the image is a progressive preview rather than the
    /// final decoded image.
    public var isPreview: Bool {
        get { ref.isPreview }
        set { mutate { $0.isPreview = newValue } }
    }

    /// Contains the original image `data`, but only if the decoder decides to
    /// attach it to the image.
    ///
    /// The default decoder (``ImageDecoders/Default``) attaches the data of the
    /// images it recognizes as animated – GIF, APNG, animated WebP, and
    /// animated HEIC – because Image I/O decodes the first frame of an
    /// animation and stops. `NukeUI` plays them; so can a rendering engine of
    /// your choice. The data is not attached to a thumbnail request, whose
    /// image is deliberately smaller than the animation the data holds.
    ///
    /// Processing an image drops the data: it describes the image that went
    /// into the processor, not the one that came out.
    ///
    /// - note: The `data`, along with the image container itself gets stored
    /// in the memory cache.
    public var data: Data? {
        get { ref.data }
        set { mutate { $0.data = newValue } }
    }

    /// Metadata provided by the user.
    public var userInfo: [UserInfoKey: any Sendable] {
        get { ref.userInfo }
        set { mutate { $0.userInfo = newValue } }
    }

    private var ref: Container

    /// Initializes the container with the given image.
    public init(image: PlatformImage, type: AssetType? = nil, isPreview: Bool = false, data: Data? = nil, userInfo: [UserInfoKey: any Sendable] = [:]) {
        self.ref = Container(image: image, type: type, isPreview: isPreview, data: data, userInfo: userInfo)
    }

    consuming func map(_ closure: (PlatformImage) throws -> PlatformImage) rethrows -> ImageContainer {
        var copy = self
        copy.image = try closure(copy.image)
        return copy
    }

    /// A key used in ``userInfo``.
    public struct UserInfoKey: Hashable, ExpressibleByStringLiteral, Sendable {
        public let rawValue: String

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.rawValue = value
        }

        /// A user info key to get the index of the preview (`Int`), starting
        /// with `1`.
        ///
        /// - important: The value counts the previews the decoder produced and
        /// is not the index of a scan in the image data. Image I/O decodes the
        /// partially downloaded data incrementally and doesn't report the scan
        /// boundaries, so with ``ImagePipeline/PreviewPolicy/incremental`` the
        /// number of previews depends on how the data arrives. The default
        /// decoder also attaches it to the final image, where it is the total
        /// number of previews that preceded it.
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
        var userInfo: [UserInfoKey: any Sendable]

        init(image: PlatformImage, type: AssetType?, isPreview: Bool, data: Data? = nil, userInfo: [UserInfoKey: any Sendable]) {
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
