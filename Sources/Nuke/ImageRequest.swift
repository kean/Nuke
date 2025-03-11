// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import Combine
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
public struct ImageRequest: CustomStringConvertible, @unchecked Sendable, ExpressibleByStringLiteral {
    // MARK: Options

    /// The relative priority of the request. The priority affects the order in
    /// which the requests are performed. ``Priority-swift.enum/normal`` by default.
    ///
    /// - note: You can change the priority of a running task using ``ImageTask/priority``.
    public var priority: Priority {
        get { ref.priority }
        set { mutate { $0.priority = newValue } }
    }

    /// Processor to be applied to the image. Empty by default.
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
    public var userInfo: [UserInfoKey: Any] {
        get { ref.userInfo ?? [:] }
        set { mutate { $0.userInfo = newValue } }
    }

    // MARK: Instance Properties

    /// Returns the request `URLRequest`.
    ///
    /// Returns `nil` for publisher-based requests.
    public var urlRequest: URLRequest? {
        switch ref.resource {
        case .url(let url): return url.map { URLRequest(url: $0) } // create lazily
        case .urlRequest(let urlRequest): return urlRequest
        case .closure: return nil
        }
    }

    /// Returns the request `URL`.
    ///
    /// Returns `nil` for publisher-based requests.
    public var url: URL? {
        switch ref.resource {
        case .url(let url): return url
        case .urlRequest(let request): return request.url
        case .closure: return nil
        }
    }

    /// Returns the ID of the underlying image. For URL-based requests, it's an
    /// image URL. For an async function – a custom ID provided in initializer.
    public var imageId: String? { ref.originalImageId }

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
    ///   - processors: Processors to be apply to the image. See <doc:image-processing> to learn more.
    ///   - priority: The priority of the request.
    ///   - options: Image loading options.
    ///   - userInfo: Custom info passed alongside the request.
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
        userInfo: [UserInfoKey: Any]? = nil
    ) {
        self.ref = Container(
            resource: Resource.url(url),
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
    ///   - processors: Processors to be apply to the image. See <doc:image-processing> to learn more.
    ///   - priority: The priority of the request.
    ///   - options: Image loading options.
    ///   - userInfo: Custom info passed alongside the request.
    ///
    /// ```swift
    /// let request = ImageRequest(
    ///     url: URLRequest(url: URL(string: "http://...")),
    ///     processors: [.resize(size: imageView.bounds.size)],
    ///     priority: .high
    /// )
    /// ```
    public init(
        urlRequest: URLRequest,
        processors: [any ImageProcessing] = [],
        priority: Priority = .normal,
        options: Options = [],
        userInfo: [UserInfoKey: Any]? = nil
    ) {
        self.ref = Container(
            resource: Resource.urlRequest(urlRequest),
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
    /// - important: If you are using a pipeline with a custom configuration that
    /// enables aggressive disk cache, fetched data will be stored in this cache.
    /// You can use ``Options-swift.struct/disableDiskCache`` to disable it.
    ///
    /// - note: If the resource is identifiable with a `URL`, consider
    /// implementing a custom data loader instead. See <doc:loading-data>.
    ///
    /// - parameters:
    ///   - id: Uniquely identifies the fetched image.
    ///   - data: An async function to be used to fetch image data.
    ///   - processors: Processors to be apply to the image. See <doc:image-processing> to learn more.
    ///   - priority: The priority of the request.
    ///   - options: Image loading options.
    ///   - userInfo: Custom info passed alongside the request.
    public init(
        id: String,
        data: @Sendable @escaping () async throws -> Data,
        processors: [any ImageProcessing] = [],
        priority: Priority = .normal,
        options: Options = [],
        userInfo: [UserInfoKey: Any]? = nil
    ) {
        // It could technically be implemented without any special change to the
        // pipeline by using a custom DataLoader and passing an async function in
        // the request userInfo. g
        self.ref = Container(
            resource: .closure(data, id: id),
            processors: processors,
            priority: priority,
            options: options,
            userInfo: userInfo
        )
    }

    // MARK: Nested Types

    /// The priority affecting the order in which the requests are performed.
    public enum Priority: Int, Comparable, Sendable {
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
    ///     request.options = [.reloadIgnoringCachedData]
    /// ```
    ///
    /// Another useful cache policy is ``ImageRequest/Options-swift.struct/returnCacheDataDontLoad``
    /// that terminates the request if no cached data is available.
    public struct Options: OptionSet, Hashable, Sendable {
        /// Returns a raw value.
        public let rawValue: UInt16

        /// Initializes options with a given raw values.
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
        /// This option only works ``ImageCaching`` and ``DataCaching``, but not
        /// `URLCache`. If you want to ignore `URLCache`, initialize the request
        /// with `URLRequest` with the respective policy
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
    ///
    /// There are a couple of built-in options that are passed using user info
    /// as well, including ``imageIdKey``, ``scaleKey``, and ``thumbnailKey``.
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

        /// Overrides the image identifier used for caching and task coalescing.
        ///
        /// By default, ``ImagePipeline`` uses an image URL as a unique identifier
        /// for caching and task coalescing. You can override this behavior by
        /// providing a custom identifier. For example, you can use it to remove
        /// transient query parameters from the URL, like access token.
        ///
        /// ```swift
        /// let request = ImageRequest(
        ///     url: URL(string: "http://example.com/image.jpeg?token=123"),
        ///     userInfo: [.imageIdKey: "http://example.com/image.jpeg"]
        /// )
        /// ```
        public static let imageIdKey: ImageRequest.UserInfoKey = "github.com/kean/nuke/imageId"

        /// The image scale to be used. By default, the scale is `1`.
        public static let scaleKey: ImageRequest.UserInfoKey = "github.com/kean/nuke/scale"

        /// Specifies whether the pipeline should retrieve or generate a thumbnail
        /// instead of a full image. The thumbnail creation is generally significantly
        /// more efficient, especially in terms of memory usage, than image resizing
        /// (``ImageProcessors/Resize``).
        ///
        /// - note: You must be using the default image decoder to make it work.
        public static let thumbnailKey: ImageRequest.UserInfoKey = "github.com/kean/nuke/thumbnail"
    }

    /// Thumbnail options.
    ///
    /// For more info, see https://developer.apple.com/documentation/imageio/cgimagesource/image_source_option_dictionary_keys
    public struct ThumbnailOptions: Hashable, Sendable {
        enum TargetSize: Hashable {
            case fixed(Float)
            case flexible(size: ImageTargetSize, contentMode: ImageProcessingOptions.ContentMode)

            var parameters: String {
                switch self {
                case .fixed(let size):
                    return "maxPixelSize=\(size)"
                case let .flexible(size, contentMode):
                    return "width=\(size.cgSize.width),height=\(size.cgSize.height),contentMode=\(contentMode)"
                }
            }
        }

        let targetSize: TargetSize

        /// Whether a thumbnail should be automatically created for an image if
        /// a thumbnail isn't present in the image source file. The thumbnail is
        /// created from the full image, subject to the limit specified by size.
        public var createThumbnailFromImageIfAbsent = true

        /// Whether a thumbnail should be created from the full image even if a
        /// thumbnail is present in the image source file. The thumbnail is created
        /// from the full image, subject to the limit specified by size.
        public var createThumbnailFromImageAlways = true

        /// Whether the thumbnail should be rotated and scaled according to the
        /// orientation and pixel aspect ratio of the full image.
        public var createThumbnailWithTransform = true

        /// Specifies whether image decoding and caching should happen at image
        /// creation time.
        public var shouldCacheImmediately = true

        /// Initializes the options with the given pixel size. The thumbnail is
        /// resized to fit the target size.
        ///
        /// This option performs slightly faster than ``ImageRequest/ThumbnailOptions/init(size:unit:contentMode:)``
        /// because it doesn't need to read the image size.
        public init(maxPixelSize: Float) {
            self.targetSize = .fixed(maxPixelSize)
        }

        /// Initializes the options with the given size.
        ///
        /// - parameters:
        ///   - size: The target size.
        ///   - unit: Unit of the target size.
        ///   - contentMode: A target content mode.
        public init(size: CGSize, unit: ImageProcessingOptions.Unit = .points, contentMode: ImageProcessingOptions.ContentMode = .aspectFill) {
            self.targetSize = .flexible(size: ImageTargetSize(size: size, unit: unit), contentMode: contentMode)
        }

        /// Generates a thumbnail from the given image data.
        public func makeThumbnail(with data: Data) -> PlatformImage? {
            Nuke.makeThumbnail(data: data, options: self)
        }

        var identifier: String {
            "com.github/kean/nuke/thumbnail?\(targetSize.parameters),options=\(createThumbnailFromImageIfAbsent)\(createThumbnailFromImageAlways)\(createThumbnailWithTransform)\(shouldCacheImmediately)"
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

    func withProcessors(_ processors: [any ImageProcessing]) -> ImageRequest {
        var request = self
        request.processors = processors
        return request
    }

    var preferredImageId: String {
        if let imageId = ref.userInfo?[.imageIdKey] as? String {
            return imageId
        }
        return imageId ?? ""
    }

    var thumbnail: ThumbnailOptions? {
        ref.userInfo?[.thumbnailKey] as? ThumbnailOptions
    }

    var scale: Float? {
        (ref.userInfo?[.scaleKey] as? NSNumber)?.floatValue
    }

    var closure: (@Sendable () async throws -> Data)? {
        if case .closure(let closure, _) = ref.resource { return closure }
        return nil
    }
}

// MARK: - ImageRequest (Private)

extension ImageRequest {
    /// Just like many Swift built-in types, ``ImageRequest`` uses CoW approach to
    /// avoid memberwise retain/releases when ``ImageRequest`` is passed around.
    private final class Container {
        // It's beneficial to put resource before priority and options because
        // of the resource size/stride of 9/16. Priority (1 byte) and Options
        // (2 bytes) slot just right in the remaining space.
        let resource: Resource
        var priority: Priority
        var options: Options
        var originalImageId: String?
        var processors: [any ImageProcessing]
        var userInfo: [UserInfoKey: Any]?
        // After trimming the request size in Nuke 10, CoW it is no longer as
        // beneficial, but there still is a measurable difference.

        /// Creates a resource with a default processor.
        init(resource: Resource, processors: [any ImageProcessing], priority: Priority, options: Options, userInfo: [UserInfoKey: Any]?) {
            self.resource = resource
            self.processors = processors
            self.priority = priority
            self.options = options
            self.originalImageId = resource.imageId
            self.userInfo = userInfo
        }

        /// Creates a copy.
        init(_ ref: Container) {
            self.resource = ref.resource
            self.processors = ref.processors
            self.priority = ref.priority
            self.options = ref.options
            self.originalImageId = ref.originalImageId
            self.userInfo = ref.userInfo
        }
    }

    // Every case takes 8 bytes and the enum 9 bytes overall (use stride!)
    enum Resource: CustomStringConvertible {
        case url(URL?)
        case urlRequest(URLRequest)
        case closure(@Sendable () async throws -> Data, id: String)

        var description: String {
            switch self {
            case .url(let url): return "\(url?.absoluteString ?? "nil")"
            case .urlRequest(let urlRequest): return "\(urlRequest)"
            case .closure(_, let id): return id
            }
        }

        var imageId: String? {
            switch self {
            case .url(let url): return url?.absoluteString
            case .urlRequest(let urlRequest): return urlRequest.url?.absoluteString
            case .closure(_, let id): return id
            }
        }
    }
}
