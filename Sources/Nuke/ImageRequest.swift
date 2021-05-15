// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageRequest

/// Represents an image request.
public struct ImageRequest: CustomStringConvertible {

    // MARK: Parameters of the Request

    /// The `URLRequest` used for loading an image.
    public var urlRequest: URLRequest {
        get {
            switch ref.resource {
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
        set {
            mutate {
                $0.resource = Resource.urlRequest(newValue)
                $0.urlString = newValue.url?.absoluteString
            }
        }
    }

    /// Returns the request URL.
    public var url: URL? {
        switch ref.resource {
        case .url(let url):
            return url
        case .urlRequest(let request):
            return request.url
        }
    }

    var urlString: String? {
        ref.urlString
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

    // MARK: Initializers

    /// Initializes a request with the given URL.
    ///
    /// - parameter priority: The priority of the request, `.normal` by default.
    /// - parameter options: Advanced image loading options.
    /// - parameter processors: Image processors to be applied after the image is loaded.
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
                options: ImageRequestOptions = .init()) {
        self.ref = Container(resource: Resource.url(url), processors: processors, cachePolicy: cachePolicy, priority: priority, options: options)
        self.ref.urlString = url.absoluteString
        // creating `.absoluteString` takes 50% of time of Request creation,
        // it's still faster than using URLs as cache keys
    }

    /// Initializes a request with the given request.
    ///
    /// - parameter priority: The priority of the request, `.normal` by default.
    /// - parameter options: Advanced image loading options.
    /// - parameter processors: Image processors to be applied after the image is loaded.
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
                options: ImageRequestOptions = .init()) {
        self.ref = Container(resource: Resource.urlRequest(urlRequest), processors: processors, cachePolicy: cachePolicy, priority: priority, options: options)
        self.ref.urlString = urlRequest.url?.absoluteString
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
        var resource: Resource
        var urlString: String? // memoized absoluteString
        var cachePolicy: CachePolicy
        var priority: ImageRequest.Priority
        var options: ImageRequestOptions
        var processors: [ImageProcessing]

        deinit {
            #if TRACK_ALLOCATIONS
            Allocations.decrement("ImageRequest.Container")
            #endif
        }

        /// Creates a resource with a default processor.
        init(resource: Resource, processors: [ImageProcessing], cachePolicy: CachePolicy, priority: Priority, options: ImageRequestOptions) {
            self.resource = resource
            self.processors = processors
            self.cachePolicy = cachePolicy
            self.priority = priority
            self.options = options

            #if TRACK_ALLOCATIONS
            Allocations.increment("ImageRequest.Container")
            #endif
        }

        /// Creates a copy.
        init(container ref: Container) {
            self.resource = ref.resource
            self.urlString = ref.urlString
            self.processors = ref.processors
            self.cachePolicy = ref.cachePolicy
            self.priority = ref.priority
            self.options = ref.options

            #if TRACK_ALLOCATIONS
            Allocations.increment("ImageRequest.Container")
            #endif
        }

        var preferredURLString: String {
            options.filteredURL ?? urlString ?? ""
        }
    }

    /// Resource representation (either URL or URLRequest).
    private enum Resource: CustomStringConvertible {
        case url(URL)
        case urlRequest(URLRequest)

        var description: String {
            switch self {
            case let .url(url):
                return "\(url)"
            case let .urlRequest(urlRequest):
                return "\(urlRequest)"
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
                filteredURL: \(String(describing: ref.options.filteredURL))
                userInfo: \(String(describing: ref.options.userInfo))
            }
        }
        """
    }

    func withProcessors(_ processors: [ImageProcessing]) -> ImageRequest {
        var request = self
        request.processors = processors
        return request
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

    /// Provide a `filteredURL` to be used as a key for caching in case the original URL
    /// contains transient query parameters.
    ///
    /// ```
    /// let request = ImageRequest(
    ///     url: URL(string: "http://example.com/image.jpeg?token=123")!,
    ///     options: ImageRequestOptions(
    ///         filteredURL: "http://example.com/image.jpeg"
    ///     )
    /// )
    /// ```
    public var filteredURL: String?

    /// Custom info passed alongside the request.
    public var userInfo: [AnyHashable: Any]

    public init(memoryCacheOptions: MemoryCacheOptions = .init(),
                filteredURL: String? = nil,
                userInfo: [AnyHashable: Any] = [:]) {
        self.memoryCacheOptions = memoryCacheOptions
        self.filteredURL = filteredURL
        self.userInfo = userInfo
    }
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
    func makeLoadKeyForProcessedImage() -> LoadKeyForProcessedImage {
        LoadKeyForProcessedImage(
            cacheKey: makeImageCacheKey(),
            cachePolicy: ref.cachePolicy,
            loadKey: makeLoadKeyForOriginalImage()
        )
    }

    /// A key for deduplicating operations for fetching the original image.
    func makeLoadKeyForOriginalImage() -> LoadKeyForOriginalImage {
        LoadKeyForOriginalImage(request: self)
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
    struct LoadKeyForProcessedImage: Hashable {
        let cacheKey: CacheKey
        let cachePolicy: CachePolicy
        let loadKey: LoadKeyForOriginalImage
    }

    // Uniquely identifies a task of retrieving the original image.
    struct LoadKeyForOriginalImage: Hashable {
        let request: ImageRequest

        func hash(into hasher: inout Hasher) {
            hasher.combine(request.ref.preferredURLString)
        }

        static func == (lhs: LoadKeyForOriginalImage, rhs: LoadKeyForOriginalImage) -> Bool {
            Parameters(lhs.request) == Parameters(rhs.request)
        }

        private struct Parameters: Hashable {
            let urlString: String?
            let cachePolicy: URLRequest.CachePolicy
            let allowsCellularAccess: Bool

            init(_ request: ImageRequest) {
                self.urlString = request.ref.urlString
                switch request.ref.resource {
                case .url:
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
