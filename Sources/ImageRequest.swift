// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageRequest

/// Represents an image request.
public struct ImageRequest {

    // MARK: Parameters of the Request

    /// The `URLRequest` used for loading an image.
    public var urlRequest: URLRequest {
        get { return ref.resource.urlRequest }
        set {
            mutate {
                $0.resource = Resource.urlRequest(newValue)
                $0.urlString = newValue.url?.absoluteString
            }
        }
    }

    /// The execution priority of the request.
    public enum Priority: Int, Comparable {
        case veryLow = 0, low, normal, high, veryHigh

        var queuePriority: Operation.QueuePriority {
            switch self {
            case .veryLow: return .veryLow
            case .low: return .low
            case .normal: return .normal
            case .high: return .high
            case .veryHigh: return .veryHigh
            }
        }

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    /// The relative priority of the operation. This value is used to influence
    /// the order in which requests are executed. `.normal` by default.
    public var priority: Priority {
        get { return ref.priority }
        set { mutate { $0.priority = newValue } }
    }

    /// The request options.
    public var options: ImageRequestOptions {
        get { return ref.options }
        set { mutate { $0.options = newValue }}
    }

    /// Processor to be applied to the image. `nil` by default.
    public var processors: [ImageProcessing] {
        get { return ref.processors }
        set { mutate { $0.processors = newValue } }
    }

    // MARK: Initializers

    /// Initializes a request with the given URL.
    /// - parameter priority: The priority of the request, `.normal` by default.
    /// - parameter options: Advanced image loading options.
    /// - parameter processors: Image processors to be applied after the image is loaded.
    public init(url: URL,
                processors: [ImageProcessing] = [],
                priority: ImageRequest.Priority = .normal,
                options: ImageRequestOptions = .init()) {
        self.ref = Container(resource: Resource.url(url), processors: processors, priority: priority, options: options)
        self.ref.urlString = url.absoluteString
        // creating `.absoluteString` takes 50% of time of Request creation,
        // it's still faster than using URLs as cache keys
    }

    /// Initializes a request with the given request.
    /// - parameter priority: The priority of the request, `.normal` by default.
    /// - parameter options: Advanced image loading options.
    /// - parameter processors: Image processors to be applied after the image is loaded.
    public init(urlRequest: URLRequest,
                processors: [ImageProcessing] = [],
                priority: ImageRequest.Priority = .normal,
                options: ImageRequestOptions = .init()) {
        self.ref = Container(resource: Resource.urlRequest(urlRequest), processors: processors, priority: priority, options: options)
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

    var urlString: String? {
        return ref.urlString
    }

    /// Just like many Swift built-in types, `ImageRequest` uses CoW approach to
    /// avoid memberwise retain/releases when `ImageRequest` is passed around.
    private class Container {
        var resource: Resource
        var urlString: String? // memoized absoluteString
        var priority: ImageRequest.Priority
        var options: ImageRequestOptions
        var processors: [ImageProcessing]

        /// Creates a resource with a default processor.
        init(resource: Resource, processors: [ImageProcessing], priority: Priority, options: ImageRequestOptions) {
            self.resource = resource
            self.priority = priority
            self.options = options
            self.processors = processors
        }

        /// Creates a copy.
        init(container ref: Container) {
            self.resource = ref.resource
            self.urlString = ref.urlString
            self.processors = ref.processors
            self.options = ref.options
            self.priority = ref.priority
        }
    }

    /// Resource representation (either URL or URLRequest).
    private enum Resource {
        case url(URL)
        case urlRequest(URLRequest)

        var urlRequest: URLRequest {
            switch self {
            case let .url(url): return URLRequest(url: url) // create lazily
            case let .urlRequest(urlRequest): return urlRequest
            }
        }
    }
}

// MARK: - ImageRequestOptions (Advanced Options)

public struct ImageRequestOptions {
    /// The policy to use when reading or writing images to the memory cache.
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

    /// Returns a key that compares requests with regards to caching images.
    ///
    /// The default key considers two requests equivalent it they have the same
    /// `URLRequests` and the same processors. `URLRequests` are compared
    /// just by their `URLs`.
    public var cacheKey: AnyHashable?

    /// Returns a key that compares requests with regards to loading images.
    ///
    /// The default key considers two requests equivalent it they have the same
    /// `URLRequests` and the same processors. `URLRequests` are compared by
    /// their `URL`, `cachePolicy`, and `allowsCellularAccess` properties.
    public var loadKey: AnyHashable?

    /// Custom info passed alongside the request.
    public var userInfo: Any?

    public init(memoryCacheOptions: MemoryCacheOptions = .init(),
                cacheKey: AnyHashable? = nil,
                loadKey: AnyHashable? = nil,
                userInfo: Any? = nil) {
        self.memoryCacheOptions = memoryCacheOptions
        self.cacheKey = cacheKey
        self.loadKey = loadKey
        self.userInfo = userInfo
    }
}

// MARK: - ImageRequestKeys (Internal)

extension ImageRequest {

    // MARK: - Cache Keys

    /// A key for processed image in memory cache.
    func makeCacheKeyForProcessedImage() -> ImageRequest.CacheKey {
        return CacheKey(request: self)
    }

    /// A key for processed image data in disk cache.
    func makeCacheKeyForProcessedImageData() -> String {
        let urlString = self.urlString ?? ""
        let processor = ImageProcessor.Composition(processors)
        return urlString + processor.identifier
    }

    /// A key for original image data in disk cache.
    func makeCacheKeyForOriginalImageData() -> String {
        return urlString ?? ""
    }

    // MARK: - Load Keys

    /// A key for deduplicating operations for fetching the processed image.
    func makeLoadKeyForProcessedImage() -> AnyHashable {
        return LoadKeyForProcessedImage(cacheKey: makeCacheKeyForProcessedImage(),
                                        loadKey: makeLoadKeyForOriginalImage())
    }

    /// A key for deduplicating operations for fetching the original image.
    func makeLoadKeyForOriginalImage() -> AnyHashable {
        if let loadKey = self.options.loadKey {
            return loadKey
        }
        return LoadKeyForOriginalImage(request: self)
    }

    // MARK: - Internals

    // Uniquely identifies a cache processed image.
    struct CacheKey: Hashable {
        let request: ImageRequest

        func hash(into hasher: inout Hasher) {
            if let customKey = request.ref.options.cacheKey {
                hasher.combine(customKey)
            } else {
                hasher.combine(request.ref.urlString?.hashValue ?? 0)
            }
        }

        /// The implementaion is a bit clever because we want to achieve good
        /// performance when using memory cache, so we can't simply go with
        /// `AnyHashable` like we do for load keys.
        static func == (lhs: CacheKey, rhs: CacheKey) -> Bool {
            let lhs = lhs.request.ref, rhs = rhs.request.ref
            if lhs.options.cacheKey != nil || rhs.options.cacheKey != nil {
                return lhs.options.cacheKey == rhs.options.cacheKey
            }
            return lhs.urlString == rhs.urlString && lhs.processors == rhs.processors
        }
    }

    // Uniquely identifies a task of retrieving the processed image.
    private struct LoadKeyForProcessedImage: Hashable {
        let cacheKey: CacheKey
        let loadKey: AnyHashable
    }

    private struct LoadKeyForOriginalImage: Hashable {
        let urlString: String?
        let cachePolicy: URLRequest.CachePolicy
        let allowsCellularAccess: Bool

        init(request: ImageRequest) {
            self.urlString = request.urlString
            let urlRequest = request.urlRequest
            self.cachePolicy = urlRequest.cachePolicy
            self.allowsCellularAccess = urlRequest.allowsCellularAccess
        }
    }
}
