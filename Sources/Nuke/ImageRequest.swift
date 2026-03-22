// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// Represents an image request that specifies what images to download, how to
/// process them, set the request priority, and more.
///
/// Creating a request:
///
/// ```swift
/// let request = ImageRequest(
///     url: URL(string: "http://example.com/image.jpeg"),
///     processors: [.resize(width: 320)],
///     priority: .high,
///     options: [.reloadIgnoringCachedData]
/// )
/// let image = try await pipeline.image(for: request)
/// ```
public struct ImageRequest: CustomStringConvertible, Sendable, ExpressibleByStringLiteral {
    // MARK: Options

    /// The relative priority of the request. The priority affects the order in
    /// which the requests are performed. ``Priority-swift.enum/normal`` by default.
    ///
    /// - note: You can change the priority of a running task using ``ImageTask/priority``.
    public var priority: Priority {
        get { ref.priority }
        set { mutate { $0.priority = newValue } }
    }

    /// Processors to be applied to the image. Empty by default.
    ///
    /// See <doc:image-processing> to learn more.
    public var processors: [any ImageProcessing] {
        get { ref.processors }
        set { mutate { $0.processors = newValue } }
    }

    /// The request options. For a complete list of options, see ``ImageRequest/Options-swift.struct``.
    public var options: Options {
        get { ref.options }
        set { mutate { $0.options = newValue } }
    }

    /// Custom info passed alongside the request.
    public var userInfo: [UserInfoKey: any Sendable] {
        get { ref.userInfo ?? [:] }
        set { mutate { $0.userInfo = newValue } }
    }

    // MARK: Instance Properties

    /// Returns the request `URLRequest`.
    ///
    /// Returns `nil` for async data requests.
    public var urlRequest: URLRequest? {
        switch ref.resource {
        case .url(let url): return url.map { URLRequest(url: $0) } // create lazily
        case .urlRequest(let urlRequest): return urlRequest
        case .data: return nil
        case .image: return nil
        }
    }

    /// Returns the request `URL`.
    ///
    /// Returns `nil` for async data requests.
    public var url: URL? {
        switch ref.resource {
        case .url(let url): return url
        case .urlRequest(let request): return request.url
        case .data: return nil
        case .image: return nil
        }
    }

    /// The image identifier used for caching and task coalescing.
    ///
    /// By default, returns the absolute URL string for URL-based requests, or
    /// the custom ID for async data requests.
    ///
    /// Set this to override the default identifier, for example, to strip
    /// transient query parameters from the cache key:
    ///
    /// ```swift
    /// var request = ImageRequest(url: URL(string: "http://example.com/image.jpeg?token=123"))
    /// request.imageID = "http://example.com/image.jpeg"
    /// ```
    ///
    /// - note: If the URL contains a short-lived auth token, consider using
    /// ``ImagePipeline/Delegate-swift.protocol/willLoadData(for:urlRequest:pipeline:)``
    /// instead. Store the base URL in the request and inject the token into
    /// the `URLRequest` dynamically — this keeps the cache key stable without
    /// having to set `imageID` on every request.
    public var imageID: String? {
        get { ref.customImageID ?? ref.originalImageID }
        set { mutate { $0.customImageID = newValue } }
    }

    /// The display scale of the image. By default, `1`.
    public var scale: Float {
        get { ref.scale }
        set { mutate { $0.scale = newValue } }
    }

    /// Thumbnail options. When set, the pipeline generates a thumbnail instead
    /// of a full image. Thumbnail creation is generally significantly more
    /// efficient, especially in terms of memory usage, than image resizing
    /// (``ImageProcessors/Resize``).
    ///
    /// - note: Requires the default image decoder.
    public var thumbnail: ThumbnailOptions? {
        get { ref.thumbnail }
        set { mutate { $0.thumbnail = newValue } }
    }

    /// Returns a debug request description.
    public var description: String {
        "ImageRequest(resource: \(ref.resource), priority: \(priority), processors: \(processors), options: \(options), userInfo: \(userInfo))"
    }

    // MARK: Initializers

    /// Initializes the request with the given string.
    public init(stringLiteral value: String) {
        self.init(url: URL(string: value))
    }

    /// Initializes a request with the given `URL`.
    ///
    /// - parameters:
    ///   - url: The request URL.
    ///   - processors: Processors to be applied to the image. See <doc:image-processing> to learn more.
    ///   - priority: The priority of the request.
    ///   - options: Image loading options.
    ///   - userInfo: Soft-deprecated in Nuke 13.0, but still available as a dedicated property.
    ///
    /// ```swift
    /// let request = ImageRequest(
    ///     url: URL(string: "http://..."),
    ///     processors: [.resize(size: imageView.bounds.size)],
    ///     priority: .high
    /// )
    /// ```
    public init(
        url: URL?,
        processors: [any ImageProcessing] = [],
        priority: Priority = .normal,
        options: Options = [],
        userInfo: [UserInfoKey: any Sendable]? = nil
    ) {
        self.ref = Container(
            resource: Resource.url(url),
            originalImageID: url?.absoluteString,
            processors: processors,
            priority: priority,
            options: options,
            userInfo: userInfo
        )
    }

    /// Initializes a request with the given `URLRequest`.
    ///
    /// - parameters:
    ///   - urlRequest: The URLRequest describing the image request.
    ///   - processors: Processors to be applied to the image. See <doc:image-processing> to learn more.
    ///   - priority: The priority of the request.
    ///   - options: Image loading options.
    ///   - userInfo: Soft-deprecated in Nuke 13.0, but still available as a dedicated property.
    ///
    /// ```swift
    /// let request = ImageRequest(
    ///     urlRequest: URLRequest(url: URL(string: "http://...")),
    ///     processors: [.resize(size: imageView.bounds.size)],
    ///     priority: .high
    /// )
    /// ```
    public init(
        urlRequest: URLRequest,
        processors: [any ImageProcessing] = [],
        priority: Priority = .normal,
        options: Options = [],
        userInfo: [UserInfoKey: any Sendable]? = nil
    ) {
        self.ref = Container(
            resource: Resource.urlRequest(urlRequest),
            originalImageID: urlRequest.url?.absoluteString,
            processors: processors,
            priority: priority,
            options: options,
            userInfo: userInfo
        )
    }

    /// Initializes a request with the given async function.
    ///
    /// For example, you can use it with the Photos framework after wrapping its
    /// API in an async function.
    ///
    /// ```swift
    /// ImageRequest(
    ///     id: asset.localIdentifier,
    ///     data: { try await PHAssetManager.default.imageData(for: asset) }
    /// )
    /// ```
    ///
    /// - important: If the pipeline uses a ``DataCaching`` disk cache, the
    /// fetched data will be stored in it. Use ``Options-swift.struct/disableDiskCache``
    /// to prevent this.
    ///
    /// - note: If the resource is identifiable with a `URL`, consider
    /// implementing a custom data loader instead. See <doc:loading-data>.
    ///
    /// - parameters:
    ///   - id: Uniquely identifies the fetched image.
    ///   - data: An async function to be used to fetch image data.
    ///   - processors: Processors to be applied to the image. See <doc:image-processing> to learn more.
    ///   - priority: The priority of the request.
    ///   - options: Image loading options.
    ///   - userInfo: Soft-deprecated in Nuke 13.0, but still available as a dedicated property.
    public init(
        id: String,
        data: @Sendable @escaping () async throws -> Data,
        processors: [any ImageProcessing] = [],
        priority: Priority = .normal,
        options: Options = [],
        userInfo: [UserInfoKey: any Sendable]? = nil
    ) {
        self.ref = Container(
            resource: .data(fetch: data),
            originalImageID: id,
            processors: processors,
            priority: priority,
            options: options,
            userInfo: userInfo
        )
    }

    /// Initializes a request with the given async function that returns an image
    /// container directly.
    ///
    /// Use this initializer to process images already in memory or integrate
    /// with systems that provide pre-decoded images, such as the Photos framework.
    ///
    /// - note: Unlike ``init(id:data:processors:priority:options:userInfo:)``, the image is never stored in the disk
    /// cache because no raw data is available.
    ///
    /// - parameters:
    ///   - id: Uniquely identifies the fetched image.
    ///   - image: An async function returning an ``ImageContainer``.
    ///   - processors: Processors to be applied to the image. See <doc:image-processing> to learn more.
    ///   - priority: The priority of the request.
    ///   - options: Image loading options.
    ///   - userInfo: Soft-deprecated in Nuke 13.0, but still available as a dedicated property.
    public init(
        id: String,
        image: @Sendable @escaping () async throws -> ImageContainer,
        processors: [any ImageProcessing] = [],
        priority: Priority = .normal,
        options: Options = [],
        userInfo: [UserInfoKey: any Sendable]? = nil
    ) {
        self.ref = Container(
            resource: .image(fetch: image),
            originalImageID: id,
            processors: processors,
            priority: priority,
            options: options,
            userInfo: userInfo
        )
    }

    // MARK: Nested Types

    /// The priority affecting the order in which the requests are performed.
    @frozen public enum Priority: Int, Comparable, Sendable {
        case veryLow = 0, low, normal, high, veryHigh

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Image request options.
    ///
    /// By default, the pipeline makes full use of all of its caching layers. You can change this behavior using options. For example, you can ignore local caches using ``ImageRequest/Options-swift.struct/reloadIgnoringCachedData`` option.
    ///
    /// ```swift
    /// request.options = [.reloadIgnoringCachedData]
    /// ```
    ///
    /// Another useful cache policy is ``ImageRequest/Options-swift.struct/returnCacheDataDontLoad``
    /// that terminates the request if no cached data is available.
    public struct Options: OptionSet, Hashable, Sendable {
        /// Returns a raw value.
        public let rawValue: UInt16

        /// Initializes options with a given raw value.
        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        /// Disables memory cache reads (see ``ImageCaching``).
        public static let disableMemoryCacheReads = Options(rawValue: 1 << 0)

        /// Disables memory cache writes (see ``ImageCaching``).
        public static let disableMemoryCacheWrites = Options(rawValue: 1 << 1)

        /// Disables both memory cache reads and writes (see ``ImageCaching``).
        public static let disableMemoryCache: Options = [.disableMemoryCacheReads, .disableMemoryCacheWrites]

        /// Disables disk cache reads (see ``DataCaching``).
        public static let disableDiskCacheReads = Options(rawValue: 1 << 2)

        /// Disables disk cache writes (see ``DataCaching``).
        public static let disableDiskCacheWrites = Options(rawValue: 1 << 3)

        /// Disables both disk cache reads and writes (see ``DataCaching``).
        public static let disableDiskCache: Options = [.disableDiskCacheReads, .disableDiskCacheWrites]

        /// The image should be loaded only from the originating source.
        ///
        /// This option only works with ``ImageCaching`` and ``DataCaching``, but not
        /// `URLCache`. If you want to ignore `URLCache`, initialize the request
        /// with `URLRequest` with the respective policy.
        public static let reloadIgnoringCachedData: Options = [.disableMemoryCacheReads, .disableDiskCacheReads]

        /// Use existing cache data and fail if no cached data is available.
        public static let returnCacheDataDontLoad = Options(rawValue: 1 << 4)

        /// Skip decompression ("bitmapping") for the given image. Decompression
        /// will happen lazily when you display the image.
        public static let skipDecompression = Options(rawValue: 1 << 5)

        /// Perform data loading immediately, ignoring ``ImagePipeline/Configuration-swift.struct/dataLoadingQueue``. It
        /// can be used to elevate priority of certain tasks.
        ///
        /// - important: If there is an outstanding task for loading the same
        /// resource but without this option, a new task will be created.
        public static let skipDataLoadingQueue = Options(rawValue: 1 << 6)
    }

    /// A key used in `userInfo` for providing custom request options.
    public struct UserInfoKey: Hashable, ExpressibleByStringLiteral, Sendable {
        /// Returns a key raw value.
        public let rawValue: String

        /// Initializes the key with a raw value.
        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        /// Initializes the key with a raw value.
        public init(stringLiteral value: String) {
            self.rawValue = value
        }
    }

    /// Thumbnail options.
    ///
    /// For more info, see https://developer.apple.com/documentation/imageio/cgimagesource/image_source_option_dictionary_keys
    public struct ThumbnailOptions: Hashable, Sendable {
        var size: ImageTargetSize
        var options: Options = .defaults

        /// Whether a thumbnail should be automatically created for an image if
        /// a thumbnail isn't present in the image source file. The thumbnail is
        /// created from the full image, subject to the limit specified by size.
        public var createThumbnailFromImageIfAbsent: Bool {
            get { options.contains(.createThumbnailFromImageIfAbsent) }
            set { options.set(.createThumbnailFromImageIfAbsent, newValue) }
        }

        /// Whether a thumbnail should be created from the full image even if a
        /// thumbnail is present in the image source file. The thumbnail is created
        /// from the full image, subject to the limit specified by size.
        public var createThumbnailFromImageAlways: Bool {
            get { options.contains(.createThumbnailFromImageAlways) }
            set { options.set(.createThumbnailFromImageAlways, newValue) }
        }

        /// Whether the thumbnail should be rotated and scaled according to the
        /// orientation and pixel aspect ratio of the full image.
        public var createThumbnailWithTransform: Bool {
            get { options.contains(.createThumbnailWithTransform) }
            set { options.set(.createThumbnailWithTransform, newValue) }
        }

        /// Specifies whether image decoding and caching should happen at image
        /// creation time.
        public var shouldCacheImmediately: Bool {
            get { options.contains(.shouldCacheImmediately) }
            set { options.set(.shouldCacheImmediately, newValue) }
        }

        /// Initializes the options with the given pixel size. The thumbnail is
        /// resized to fit the target size.
        ///
        /// This option performs slightly faster than ``ImageRequest/ThumbnailOptions/init(size:unit:contentMode:)``
        /// because it doesn't need to read the image size.
        public init(maxPixelSize: Float) {
            self.size = ImageTargetSize(maxPixelSize: maxPixelSize)
        }

        /// Initializes the options with the given size.
        ///
        /// - parameters:
        ///   - size: The target size.
        ///   - unit: Unit of the target size.
        ///   - contentMode: A target content mode.
        public init(size: CGSize, unit: ImageProcessingOptions.Unit = .points, contentMode: ImageProcessingOptions.ContentMode = .aspectFill) {
            self.size = ImageTargetSize(size: size, unit: unit)
            options.insert(.flexible)
            if contentMode == .aspectFit { options.insert(.aspectFit) }
        }

        /// The content mode for flexible-size thumbnails.
        var contentMode: ImageProcessingOptions.ContentMode {
            options.contains(.aspectFit) ? .aspectFit : .aspectFill
        }

        /// Generates a thumbnail from the given image data.
        public func makeThumbnail(with data: Data) -> PlatformImage? {
            Nuke.makeThumbnail(data: data, options: self)
        }

        var identifier: String {
            let sizeStr = options.contains(.flexible)
                ? "width=\(size.cgSize.width),height=\(size.cgSize.height),contentMode=\(contentMode)"
                : "maxPixelSize=\(size.width)"
            return "com.github/kean/nuke/thumbnail?\(sizeStr),options=\(createThumbnailFromImageIfAbsent)\(createThumbnailFromImageAlways)\(createThumbnailWithTransform)\(shouldCacheImmediately)"
        }

        struct Options: OptionSet, Hashable, Sendable {
            let rawValue: UInt8

            init(rawValue: UInt8) { self.rawValue = rawValue }

            static let createThumbnailFromImageIfAbsent = Options(rawValue: 1 << 0)
            static let createThumbnailFromImageAlways = Options(rawValue: 1 << 1)
            static let createThumbnailWithTransform = Options(rawValue: 1 << 2)
            static let shouldCacheImmediately = Options(rawValue: 1 << 3)
            static let aspectFit = Options(rawValue: 1 << 4)
            static let flexible = Options(rawValue: 1 << 5)

            static let defaults: Options = [
                .createThumbnailFromImageIfAbsent,
                .createThumbnailFromImageAlways,
                .createThumbnailWithTransform,
                .shouldCacheImmediately
            ]

            mutating func set(_ option: Options, _ value: Bool) {
                if value { insert(option) } else { remove(option) }
            }
        }
    }

    // MARK: Internal

    private var ref: Container

    private mutating func mutate(_ closure: (Container) -> Void) {
        if !isKnownUniquelyReferenced(&ref) {
            ref = Container(ref)
        }
        closure(ref)
    }

    var resource: Resource { ref.resource }

    consuming func withProcessors(_ processors: [any ImageProcessing]) -> ImageRequest {
        var request = self
        request.processors = processors
        return request
    }

    consuming func withoutThumbnail() -> ImageRequest {
        var copy = self
        copy.thumbnail = nil
        return copy
    }

    /// The underlying resource image ID (URL string or data ID), never the
    /// user-supplied ``imageID`` override. Used for data-loading task keys
    /// where the actual URL determines what gets fetched.
    var originalImageID: String? { ref.originalImageID }

    static var _containerInstanceSize: Int { class_getInstanceSize(Container.self) }
}

// MARK: - ImageRequest (Private)

extension ImageRequest {
    /// Just like many Swift built-in types, ``ImageRequest`` uses CoW approach to
    /// avoid memberwise retain/releases when ``ImageRequest`` is passed around.
    private final class Container: @unchecked Sendable {
        // It's beneficial to put these fields in that order to align them
        // as they perfeclty align at the boundary due to their size
        let resource: Resource
        var priority: Priority
        var options: Options
        var scale: Float = 1.0

        // It is stored partially for performance reasons (`absoluteString` can be expensive to compute)
        var originalImageID: String?
        var customImageID: String?
        var processors: [any ImageProcessing]
        var userInfo: [UserInfoKey: any Sendable]?
        var thumbnail: ThumbnailOptions?

        init(resource: Resource, originalImageID: String?, processors: [any ImageProcessing], priority: Priority, options: Options, userInfo: [UserInfoKey: any Sendable]?) {
            self.resource = resource
            self.processors = processors
            self.priority = priority
            self.options = options
            self.originalImageID = originalImageID
            self.userInfo = userInfo
        }

        /// Creates a copy.
        init(_ ref: Container) {
            self.resource = ref.resource
            self.processors = ref.processors
            self.priority = ref.priority
            self.options = ref.options
            self.originalImageID = ref.originalImageID
            self.userInfo = ref.userInfo
            self.customImageID = ref.customImageID
            self.scale = ref.scale
            self.thumbnail = ref.thumbnail
        }
    }

    enum Resource: CustomStringConvertible {
        case url(URL?)
        case urlRequest(URLRequest)
        case data(fetch: @Sendable () async throws -> Data)
        case image(fetch: @Sendable () async throws -> ImageContainer)

        var description: String {
            switch self {
            case .url(let url): return "\(url?.absoluteString ?? "nil")"
            case .urlRequest(let urlRequest): return "\(urlRequest)"
            case .data: return "<closure>"
            case .image: return "<closure>"
            }
        }
    }
}
