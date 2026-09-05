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
    /// images it recognizes as animated – GIF, APNG, animated WebP, and HEIC
    /// and AVIF sequences – because Image I/O decodes only the first frame of
    /// an animation. `NukeUI` plays them; so can a rendering engine of your
    /// choice. The data is not attached to a thumbnail request. The
    /// recognition is a header sniff, so a single-frame GIF gets its data too;
    /// ``animation`` is the parsed answer.
    ///
    /// Processing an image drops the data, which describes the image that went
    /// into the processor.
    ///
    /// - note: The `data`, along with the image container itself gets stored
    /// in the memory cache.
    public var data: Data? {
        get { ref.data }
        set { mutate { $0.data = newValue } }
    }

    /// The animation the image data describes, if the image is an animated one.
    ///
    /// The default decoder (``ImageDecoders/Default``) parses the metadata of
    /// every image it attaches ``data`` to and puts the result here, so a
    /// non-`nil` value answers "can this be played?". The parse happens on the
    /// decoding queue, once per decoded image, and the result is cached with
    /// the container. Set
    /// ``ImagePipeline/Configuration-swift.struct/isAnimatedImageParsingEnabled``
    /// to `false` to skip it.
    ///
    /// Processing an image drops the animation along with the data.
    ///
    /// - note: ``AnimatedImageSource/data`` is the same buffer ``data`` holds,
    /// so an animation adds only its frame delays to what the container costs.
    public var animation: AnimatedImageSource? {
        get { ref.animation }
        set { mutate { $0.animation = newValue } }
    }

    /// Metadata provided by the user.
    public var userInfo: [UserInfoKey: any Sendable] {
        get { ref.userInfo }
        set { mutate { $0.userInfo = newValue } }
    }

    private var ref: Container

    /// Initializes the container with the given image.
    public init(image: PlatformImage, type: AssetType? = nil, isPreview: Bool = false, data: Data? = nil, animation: AnimatedImageSource? = nil, userInfo: [UserInfoKey: any Sendable] = [:]) {
        self.ref = Container(image: image, type: type, isPreview: isPreview, data: data, animation: animation, userInfo: userInfo)
    }

    /// Replaces the image, dropping ``data`` and ``animation``, which describe
    /// the image that went in.
    consuming func map(_ closure: (PlatformImage) throws -> PlatformImage) rethrows -> ImageContainer {
        var copy = self
        copy.image = try closure(copy.image)
        copy.data = nil
        copy.animation = nil
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
        var animation: AnimatedImageSource?
        var userInfo: [UserInfoKey: any Sendable]

        init(image: PlatformImage, type: AssetType?, isPreview: Bool, data: Data? = nil, animation: AnimatedImageSource? = nil, userInfo: [UserInfoKey: any Sendable]) {
            self.image = image
            self.type = type
            self.isPreview = isPreview
            self.data = data
            self.animation = animation
            self.userInfo = userInfo
        }

        init(_ ref: Container) {
            self.image = ref.image
            self.type = ref.type
            self.isPreview = ref.isPreview
            self.data = ref.data
            self.animation = ref.animation
            self.userInfo = ref.userInfo
        }
    }
}
