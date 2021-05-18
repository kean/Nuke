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
    public var urlRequest: URLRequest? {
        switch ref.resource {
        case .publisher:
            return nil
        case let .url(url):
            var request = URLRequest(url: url) // create lazily
            if cachePolicy == .reloadIgnoringCachedData {
                request.cachePolicy = .reloadIgnoringLocalCacheData
            }
            return request
        case let .urlRequest(urlRequest):
            return urlRequest
        }
    }

    /// Returns the request URL.
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

    /// The execution priority of the request. The priority affects the order in which the image
    /// requests are executed.
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

    /// The relative priority of the operation. The priority affects the order in which the image
    /// requests are executed.`.normal` by default.
    public var priority: Priority {
        get { ref.priority }
        set { mutate { $0.priority = newValue } }
    }

    public enum CachePolicy {
        case `default`
        /// The image should be loaded only from the originating source.
        ///
        /// If you initialize the request with `URLRequest`, make sure to provide
        /// the correct policy in the request too.
        case reloadIgnoringCachedData

        /// Use existing cache data and fail if no cached data is available.
        case returnCacheDataDontLoad
    }

    public var cachePolicy: CachePolicy {
        get { ref.cachePolicy }
        set { mutate { $0.cachePolicy = newValue } }
    }

    /// The request options. See `ImageRequestOptions` for more info.
    public var options: ImageRequestOptions {
        get { ref.options }
        set { mutate { $0.options = newValue } }
    }

    /// Processor to be applied to the image. `nil` by default.
    public var processors: [ImageProcessing] {
        get { ref.processors }
        set { mutate { $0.processors = newValue } }
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
    /// - parameter priority: The priority of the request, `.normal` by default.
    /// - parameter options: Advanced image loading options.
    /// - parameter processors: Image processors to be applied after the image is loaded.
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
                cachePolicy: CachePolicy = .default,
                priority: Priority = .normal,
                options: ImageRequestOptions = .init(),
                userInfo: [UserInfoKey: Any]? = nil) {
        self.ref = Container(
            resource: Resource.url(url),
            imageId: url.absoluteString,
            processors: processors,
            cachePolicy: cachePolicy,
            priority: priority,
            options: options,
            userInfo: userInfo
        )
    }

    /// Initializes a request with the given request.
    ///
    /// - parameter priority: The priority of the request, `.normal` by default.
    /// - parameter options: Advanced image loading options.
    /// - parameter processors: Image processors to be applied after the image is loaded.
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
                cachePolicy: CachePolicy = .default,
                priority: ImageRequest.Priority = .normal,
                options: ImageRequestOptions = .init(),
                userInfo: [UserInfoKey: Any]? = nil) {
        self.ref = Container(
            resource: Resource.urlRequest(urlRequest),
            imageId: urlRequest.url?.absoluteString,
            processors: processors,
            cachePolicy: cachePolicy,
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
    /// - parameter priority: The priority of the request, `.normal` by default.
    /// - parameter options: Advanced image loading options.
    /// - parameter processors: Image processors to be applied after the image is loaded.
    /// - parameter userInfo: Custom info passed alongside the request. `nil` by default.
    ///
    /// For example, here is how you can use it with Photos framework (the
    /// `imageDataPublisher()` API is a convenience extension).
    ///
    /// - warning: If you don't want data to be stored in the disk cache, make
    /// sure to create a pipeline without it or disable it on a per-request basis.
    /// You can also disable it dynamically using `ImagePipeline.Delegate`.
    ///
    /// ```swift
    /// let request = ImageRequest(
    ///     id: asset.localIdentifier,
    ///     data: PHAssetManager.imageDataPublisher(for: asset)
    /// )
    /// ```
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    public init<P>(id: String, data: P,
                   processors: [ImageProcessing] = [],
                   cachePolicy: CachePolicy = .default,
                   priority: ImageRequest.Priority = .normal,
                   options: ImageRequestOptions = .init(),
                   userInfo: [UserInfoKey: Any]? = nil) where P: Publisher, P.Output == Data {
        // It could technically be implemented without any special change to the
        // pipeline by using a custom DataLoader, disabling resumable data, and
        // passing a publisher in the request userInfo. The first-class support
        // is much nicer though.
        self.ref = Container(
            resource: .publisher(data: BCAnyPublisher(data)),
            imageId: id,
            processors: processors,
            cachePolicy: cachePolicy,
            priority: priority,
            options: options,
            userInfo: userInfo
        )
    }
    #endif

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
        var cachePolicy: CachePolicy
        var priority: ImageRequest.Priority
        var options: ImageRequestOptions
        var processors: [ImageProcessing]
        var userInfo: [UserInfoKey: Any]?

        deinit {
            #if TRACK_ALLOCATIONS
            Allocations.decrement("ImageRequest.Container")
            #endif
        }

        /// Creates a resource with a default processor.
        init(resource: Resource, imageId: String?, processors: [ImageProcessing], cachePolicy: CachePolicy, priority: Priority, options: ImageRequestOptions, userInfo: [UserInfoKey: Any]?) {
            self.resource = resource
            self.imageId = imageId
            self.processors = processors
            self.cachePolicy = cachePolicy
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
            self.cachePolicy = ref.cachePolicy
            self.priority = ref.priority
            self.options = ref.options
            self.userInfo = ref.userInfo

            #if TRACK_ALLOCATIONS
            Allocations.increment("ImageRequest.Container")
            #endif
        }

        var preferredURLString: String {
            if let imageId = userInfo?[.imageId] as? String {
                return imageId
            }
            return imageId ?? ""
        }
    }

    /// Resource representation (either URL or URLRequest).
    private enum Resource: CustomStringConvertible {
        case url(URL)
        case urlRequest(URLRequest)
        case publisher(data: BCAnyPublisher<Data>)

        var description: String {
            switch self {
            case let .url(url): return "\(url)"
            case let .urlRequest(urlRequest): return "\(urlRequest)"
            case let .publisher(data): return "Publisher(\(data))"
            }
        }
    }

    public var description: String {
        return """
        ImageRequest {
            resource: \(ref.resource)
            priority: \(ref.priority)
            processors: \(ref.processors)
            options: {
                memoryCacheOptions: \(ref.options.memoryCacheOptions)
            }
        }
        """
    }

    func withProcessors(_ processors: [ImageProcessing]) -> ImageRequest {
        var request = self
        request.processors = processors
        return request
    }

    var imageId: String? {
        ref.imageId
    }

    var publisher: BCAnyPublisher<Data>? {
        guard case .publisher(let publisher) = ref.resource else {
            return nil
        }
        return publisher
    }
}

// MARK: - ImageRequestOptions (Advanced Options)

public struct ImageRequestOptions {
    /// The policy to use when reading or writing images to the memory cache.
    ///
    /// Soft-deprecated in Nuke 9.2.
    public struct MemoryCacheOptions {
        /// `true` by default.
        public var isReadAllowed = true

        /// `true` by default.
        public var isWriteAllowed = true

        public init(isReadAllowed: Bool = true, isWriteAllowed: Bool = true) {
            self.isReadAllowed = isReadAllowed
            self.isWriteAllowed = isWriteAllowed
        }
    }

    /// `MemoryCacheOptions()` (read allowed, write allowed) by default.
    public var memoryCacheOptions: MemoryCacheOptions

    public init(memoryCacheOptions: MemoryCacheOptions = .init()) {
        self.memoryCacheOptions = memoryCacheOptions
    }
}

public extension ImageRequest {
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

// MARK: - ImageRequestKeys (Internal)

extension ImageRequest {

    // MARK: - Cache Keys

    /// A key for processed image in memory cache.
    func makeImageCacheKey() -> ImageRequest.CacheKey {
        CacheKey(request: self)
    }

    /// A key for processed image data in disk cache.
    func makeDataCacheKey() -> String {
        "\(ref.preferredURLString)\(ImageProcessors.Composition(processors).identifier)"
    }

    // MARK: - Load Keys

    /// A key for deduplicating operations for fetching the processed image.
    func makeImageLoadKey() -> ImageLoadKey {
        ImageLoadKey(
            cacheKey: makeImageCacheKey(),
            cachePolicy: ref.cachePolicy,
            loadKey: makeDataLoadKey()
        )
    }

    /// A key for deduplicating operations for fetching the original image.
    func makeDataLoadKey() -> DataLoadKey {
        DataLoadKey(request: self)
    }

    // MARK: - Internals (Keys)

    // Uniquely identifies a cache processed image.
    struct CacheKey: Hashable {
        let request: ImageRequest

        func hash(into hasher: inout Hasher) {
            hasher.combine(request.ref.preferredURLString)
        }

        static func == (lhs: CacheKey, rhs: CacheKey) -> Bool {
            let lhs = lhs.request.ref, rhs = rhs.request.ref
            return lhs.preferredURLString == rhs.preferredURLString && lhs.processors == rhs.processors
        }
    }

    // Uniquely identifies a task of retrieving the processed image.
    struct ImageLoadKey: Hashable {
        let cacheKey: CacheKey
        let cachePolicy: CachePolicy
        let loadKey: DataLoadKey
    }

    // Uniquely identifies a task of retrieving the original image dataa.
    struct DataLoadKey: Hashable {
        let request: ImageRequest

        func hash(into hasher: inout Hasher) {
            hasher.combine(request.ref.preferredURLString)
        }

        static func == (lhs: DataLoadKey, rhs: DataLoadKey) -> Bool {
            Parameters(lhs.request) == Parameters(rhs.request)
        }

        private struct Parameters: Hashable {
            let imageId: String?
            let cachePolicy: URLRequest.CachePolicy
            let allowsCellularAccess: Bool

            init(_ request: ImageRequest) {
                self.imageId = request.ref.imageId
                switch request.ref.resource {
                case .url, .publisher:
                    self.cachePolicy = .useProtocolCachePolicy
                    self.allowsCellularAccess = true
                case let .urlRequest(urlRequest):
                    self.cachePolicy = urlRequest.cachePolicy
                    self.allowsCellularAccess = urlRequest.allowsCellularAccess
                }
            }
        }
    }
}

struct ImageProcessingKey: Equatable, Hashable {
    let imageId: ObjectIdentifier
    let processorId: AnyHashable

    init(image: ImageResponse, processor: ImageProcessing) {
        self.imageId = ObjectIdentifier(image)
        self.processorId = processor.hashableIdentifier
    }
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
