// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

#if canImport(Combine)
import Combine
#endif

// MARK: - ImageRequest

/// Represents an image request.
public struct ImageRequest: CustomStringConvertible {

    // MARK: Parameters of the Request

    /// The `URLRequest` used for loading an image.
    ///
    /// Returns `nil` for publisher-based requests.
    public var urlRequest: URLRequest? {
        switch ref.resource {
        case .publisher:
            return nil
        case let .url(url):
            return URLRequest(url: url) // create lazily
        case let .urlRequest(urlRequest):
            return urlRequest
        }
    }

    /// Returns the request `URL`.
    ///
    /// Returns `nil` for publisher-based requests.
    public var url: URL? {
        switch ref.resource {
        case .publisher:
            return nil
        case .url(let url):
            return url
        case .urlRequest(let request):
            return request.url
        }
    }

    /// The priority of the request. The priority affects the order in which the
    /// requests are performed.
    public enum Priority: Int, Comparable {
        case veryLow = 0, low, normal, high, veryHigh

        var taskPriority: TaskPriority {
            switch self {
            case .veryLow: return .veryLow
            case .low: return .low
            case .normal: return .normal
            case .high: return .high
            case .veryHigh: return .veryHigh
            }
        }

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// The relative priority of the request. The priority affects the order in
    /// which the requests are performed.`.normal` by default.
    public var priority: Priority {
        get { ref.priority }
        set { mutate { $0.priority = newValue } }
    }

    /// Processor to be applied to the image. Empty by default.
    public var processors: [ImageProcessing] {
        get { ref.processors }
        set { mutate { $0.processors = newValue } }
    }

    /// The request options. See `ImageRequest.Options` for more info.
    public var options: ImageRequest.Options {
        get { ref.options }
        set { mutate { $0.options = newValue } }
    }

    /// Custom info passed alongside the request.
    public var userInfo: [ImageRequest.UserInfoKey: Any] {
        get {
            if let userInfo = ref.userInfo {
                return userInfo
            }
            ref.userInfo = [:]
            return [:]
        }
        set {
            mutate { $0.userInfo = newValue }
        }
    }

    // MARK: Initializers

    /// Initializes a request with the given URL.
    ///
    /// - parameter processors: Image processors to be applied to the loaded image. Empty by default.
    /// - parameter priority: The priority of the request, `.normal` by default.
    /// - parameter options: Image loading options. Empty by default.
    /// - parameter userInfo: Custom info passed alongside the request. `nil` by default.
    ///
    /// `ImageRequest` allows you to set image processors, change the request priority and more:
    ///
    /// ```swift
    /// let request = ImageRequest(
    ///     url: URL(string: "http://...")!,
    ///     processors: [ImageProcessors.Resize(size: imageView.bounds.size)],
    ///     priority: .high
    /// )
    /// ```
    public init(url: URL,
                processors: [ImageProcessing] = [],
                priority: Priority = .normal,
                options: ImageRequest.Options = [],
                userInfo: [UserInfoKey: Any]? = nil) {
        self.ref = Container(
            resource: Resource.url(url),
            imageId: url.absoluteString,
            processors: processors,
            priority: priority,
            options: options,
            userInfo: userInfo
        )
    }

    /// Initializes a request with the given request.
    ///
    /// - parameter processors: Image processors to be applied to the loaded image. Empty by default.
    /// - parameter priority: The priority of the request, `.normal` by default.
    /// - parameter options: Image loading options. Empty by default.
    /// - parameter userInfo: Custom info passed alongside the request. `nil` by default.
    ///
    /// `ImageRequest` allows you to set image processors, change the request priority and more:
    ///
    /// ```swift
    /// let request = ImageRequest(
    ///     url: URLRequest(url: URL(string: "http://...")!),
    ///     processors: [ImageProcessors.Resize(size: imageView.bounds.size)],
    ///     priority: .high
    /// )
    /// ```
    public init(urlRequest: URLRequest,
                processors: [ImageProcessing] = [],
                priority: ImageRequest.Priority = .normal,
                options: ImageRequest.Options = [],
                userInfo: [UserInfoKey: Any]? = nil) {
        self.ref = Container(
            resource: Resource.urlRequest(urlRequest),
            imageId: urlRequest.url?.absoluteString,
            processors: processors,
            priority: priority,
            options: options,
            userInfo: userInfo
        )
    }

    #if canImport(Combine)
    /// Initializes a request with the given data publisher.
    ///
    /// - parameter id: Uniquely identifies the image data.
    /// - parameter data: A data publisher to be used for fetching image data.
    /// - parameter processors: Image processors to be applied to the loaded image. Empty by default.
    /// - parameter priority: The priority of the request, `.normal` by default.
    /// - parameter options: Image loading options. Empty by default.
    /// - parameter userInfo: Custom info passed alongside the request. `nil` by default.
    ///
    /// For example, here is how you can use it with Photos framework (the
    /// `imageDataPublisher()` API is a convenience extension).
    ///
    /// ```swift
    /// let request = ImageRequest(
    ///     id: asset.localIdentifier,
    ///     data: PHAssetManager.imageDataPublisher(for: asset)
    /// )
    /// ```
    ///
    /// - warning: If you don't want data to be stored in the disk cache, make
    /// sure to create a pipeline without it or disable it on a per-request basis.
    /// You can also disable it dynamically using `ImagePipeline.Delegate`.
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    public init<P>(id: String, data: P,
                   processors: [ImageProcessing] = [],
                   priority: ImageRequest.Priority = .normal,
                   options: ImageRequest.Options = [],
                   userInfo: [UserInfoKey: Any]? = nil) where P: Publisher, P.Output == Data {
        // It could technically be implemented without any special change to the
        // pipeline by using a custom DataLoader, disabling resumable data, and
        // passing a publisher in the request userInfo. The first-class support
        // is much nicer though.
        self.ref = Container(
            resource: .publisher(BCAnyPublisher(data)),
            imageId: id,
            processors: processors,
            priority: priority,
            options: options,
            userInfo: userInfo
        )
    }
    #endif

    // MARK: Options

    /// Image request options.
    public struct Options: OptionSet, Hashable {
        /// Returns a raw value.
        public let rawValue: Int

        /// Initialializes options with a given raw values.
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Disables memory cache reads (`ImageCaching`).
        public static let disableMemoryCacheReads = Options(rawValue: 1 << 0)

        /// Disables memory cache writes (`ImageCaching`).
        public static let disableMemoryCacheWrites = Options(rawValue: 1 << 1)

        /// Disables both memory cache reads and writes (`ImageCaching`).
        public static let disableMemoryCache: Options = [.disableMemoryCacheReads, .disableMemoryCacheWrites]

        /// Disables disk cache reads (`DataCaching`).
        public static let disableDiskCacheReads = Options(rawValue: 1 << 2)

        /// Disables disk cache writes (`DataCaching`).
        public static let disableDiskCacheWrites = Options(rawValue: 1 << 3)

        /// Disables both disk cache reads and writes (`DataCaching`).
        public static let disableDiskCache: Options = [.disableDiskCacheReads, .disableDiskCacheWrites]

        /// The image should be loaded only from the originating source.
        ///
        /// If you initialize the request with `URLRequest`, make sure to provide
        /// the correct policy in the request too.
        public static let reloadIgnoringCachedData: Options = [.disableMemoryCacheReads, .disableDiskCacheReads]

        /// Use existing cache data and fail if no cached data is available.
        public static let returnCacheDataDontLoad = Options(rawValue: 1 << 4)
    }

    // CoW:

    private var ref: Container

    private mutating func mutate(_ closure: (Container) -> Void) {
        if !isKnownUniquelyReferenced(&ref) {
            ref = Container(container: ref)
        }
        closure(ref)
    }

    /// Just like many Swift built-in types, `ImageRequest` uses CoW approach to
    /// avoid memberwise retain/releases when `ImageRequest` is passed around.
    private class Container {
        let resource: Resource
        let imageId: String? // memoized absoluteString
        var priority: ImageRequest.Priority
        var options: ImageRequest.Options
        var processors: [ImageProcessing]
        var userInfo: [UserInfoKey: Any]?

        deinit {
            #if TRACK_ALLOCATIONS
            Allocations.decrement("ImageRequest.Container")
            #endif
        }

        /// Creates a resource with a default processor.
        init(resource: Resource, imageId: String?, processors: [ImageProcessing], priority: Priority, options: ImageRequest.Options, userInfo: [UserInfoKey: Any]?) {
            self.resource = resource
            self.imageId = imageId
            self.processors = processors
            self.priority = priority
            self.options = options
            self.userInfo = userInfo

            #if TRACK_ALLOCATIONS
            Allocations.increment("ImageRequest.Container")
            #endif
        }

        /// Creates a copy.
        init(container ref: Container) {
            self.resource = ref.resource
            self.imageId = ref.imageId
            self.processors = ref.processors
            self.priority = ref.priority
            self.options = ref.options
            self.userInfo = ref.userInfo

            #if TRACK_ALLOCATIONS
            Allocations.increment("ImageRequest.Container")
            #endif
        }
    }

    /// Resource representation (either URL or URLRequest).
    enum Resource: CustomStringConvertible {
        case url(URL)
        case urlRequest(URLRequest)
        case publisher(BCAnyPublisher<Data>)

        var description: String {
            switch self {
            case let .url(url): return "\(url)"
            case let .urlRequest(urlRequest): return "\(urlRequest)"
            case let .publisher(data): return "Publisher(\(data))"
            }
        }
    }

    public var description: String {
        """
        ImageRequest {
            resource: \(ref.resource),
            priority: \(ref.priority),
            processors: \(ref.processors),
            options: \(ref.options),
            userInfo: \(ref.userInfo ?? [:])
        }
        """
    }

    func withProcessors(_ processors: [ImageProcessing]) -> ImageRequest {
        var request = self
        request.processors = processors
        return request
    }

    var resource: Resource {
        ref.resource
    }

    var imageId: String? {
        ref.imageId
    }

    var preferredImageId: String {
        if let imageId = ref.userInfo?[.imageId] as? String {
            return imageId
        }
        return imageId ?? ""
    }

    var publisher: BCAnyPublisher<Data>? {
        guard case .publisher(let publisher) = ref.resource else {
            return nil
        }
        return publisher
    }
}

// MARK: - ImageRequest.UserInfoKey

public extension ImageRequest {
    /// A key use in `userInfo`.
    struct UserInfoKey: Hashable, ExpressibleByStringLiteral {
        public let rawValue: String

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.rawValue = value
        }
    }
}

public extension ImageRequest.UserInfoKey {
    /// By default, Nuke uses URL as unique image identifiers for the purpsoses
    /// of caching and task coalescing. You can override the default behavior
    /// by providing an `imageId`instead. For example, you can use it to remove
    /// transient query parameters from the request.
    ///
    /// ```
    /// let request = ImageRequest(
    ///     url: URL(string: "http://example.com/image.jpeg?token=123")!,
    ///     userInfo: [.imageId: "http://example.com/image.jpeg"]
    /// )
    /// ```
    static let imageId: ImageRequest.UserInfoKey = "github.com/kean/nuke/imageId"
}

// MARK: - ImageRequestConvertible

public protocol ImageRequestConvertible {
    func asImageRequest() -> ImageRequest
}

extension ImageRequest: ImageRequestConvertible {
    public func asImageRequest() -> ImageRequest {
        self
    }
}

extension URL: ImageRequestConvertible {
    public func asImageRequest() -> ImageRequest {
        ImageRequest(url: self)
    }
}

extension URLRequest: ImageRequestConvertible {
    public func asImageRequest() -> ImageRequest {
        ImageRequest(urlRequest: self)
    }
}

extension String: ImageRequestConvertible {
    public func asImageRequest() -> ImageRequest {
        ImageRequest(url: URL(string: self) ?? URL(fileURLWithPath: "/dev/null"))
    }
}
