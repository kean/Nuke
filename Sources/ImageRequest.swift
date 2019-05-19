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
                priority: ImageRequest.Priority = .normal,
                options: ImageRequestOptions = .init(),
                processors: [ImageProcessing] = []) {
        self.ref = Container(resource: Resource.url(url), priority: priority, options: options, processors: processors)
        self.ref.urlString = url.absoluteString
        // creating `.absoluteString` takes 50% of time of Request creation,
        // it's still faster than using URLs as cache keys
    }

    /// Initializes a request with the given request.
    /// - parameter priority: The priority of the request, `.normal` by default.
    /// - parameter options: Advanced image loading options.
    /// - parameter processors: Image processors to be applied after the image is loaded.
    public init(urlRequest: URLRequest,
                priority: ImageRequest.Priority = .normal,
                options: ImageRequestOptions = .init(),
                processors: [ImageProcessing] = []) {
        self.ref = Container(resource: Resource.urlRequest(urlRequest), priority: priority, options: options, processors: processors)
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
        init(resource: Resource, priority: Priority, options: ImageRequestOptions, processors: [ImageProcessing]) {
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

// MARK: - ImageRequest (Internal)

extension ImageRequest {
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

        static func == (lhs: CacheKey, rhs: CacheKey) -> Bool {
            let lhs = lhs.request.ref, rhs = rhs.request.ref
            if let lhsCustomKey = lhs.options.cacheKey, let rhsCustomKey = rhs.options.cacheKey {
                return lhsCustomKey == rhsCustomKey
            }
            guard lhs.urlString == rhs.urlString else {
                return false
            }

            return lhs.processors == rhs.processors
        }
    }

    // Uniquely identifies a task of retrieving the processed image.
    struct ImageLoadKey: Hashable {
        let cacheKey: CacheKey
        let loadKey: LoadKey

        init(request: ImageRequest) {
            self.cacheKey = CacheKey(request: request)
            self.loadKey = LoadKey(request: request)
        }
    }

    /// Uniquely identifies a task of loading image data.
    struct LoadKey: Hashable {
        let request: ImageRequest

        func hash(into hasher: inout Hasher) {
            if let customKey = request.ref.options.loadKey {
                hasher.combine(customKey)
            } else {
                hasher.combine(request.ref.urlString?.hashValue ?? 0)
            }
        }

        static func == (lhs: LoadKey, rhs: LoadKey) -> Bool {
            func isEqual(_ lhs: URLRequest, _ rhs: URLRequest) -> Bool {
                return lhs.cachePolicy == rhs.cachePolicy
                    && lhs.allowsCellularAccess == rhs.allowsCellularAccess
            }

            let lhs = lhs.request.ref, rhs = rhs.request.ref
            if let lhsCustomKey = lhs.options.loadKey, let rhsCustomKey = rhs.options.loadKey {
                return lhsCustomKey == rhsCustomKey
            }
            return lhs.urlString == rhs.urlString
                && isEqual(lhs.resource.urlRequest, rhs.resource.urlRequest)
        }
    }
}
