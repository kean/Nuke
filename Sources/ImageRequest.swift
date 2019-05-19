// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

#if !os(macOS)
import UIKit
#endif

/// Represents an image request.
public struct ImageRequest {

    // MARK: Parameters of the Request

    var urlString: String? {
        return ref.urlString
    }

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

    /// Processor to be applied to the image. `nil` by default.
    public var processors: [ImageProcessing] {
        get { return ref.processors }
        set { mutate { $0.processors = newValue } }
    }

    /// The policy to use when reading or writing images to the memory cache.
    public struct MemoryCacheOptions {
        /// `true` by default.
        public var isReadAllowed = true

        /// `true` by default.
        public var isWriteAllowed = true

        public init() {}
    }

    /// `MemoryCacheOptions()` (read allowed, write allowed) by default.
    public var memoryCacheOptions: MemoryCacheOptions {
        get { return ref.memoryCacheOptions }
        set { mutate { $0.memoryCacheOptions = newValue } }
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

    /// Returns a key that compares requests with regards to caching images.
    ///
    /// The default key considers two requests equivalent it they have the same
    /// `URLRequests` and the same processors. `URLRequests` are compared
    /// just by their `URLs`.
    public var cacheKey: AnyHashable? {
        get { return ref.cacheKey }
        set { mutate { $0.cacheKey = newValue } }
    }

    /// Returns a key that compares requests with regards to loading images.
    ///
    /// The default key considers two requests equivalent it they have the same
    /// `URLRequests` and the same processors. `URLRequests` are compared by
    /// their `URL`, `cachePolicy`, and `allowsCellularAccess` properties.
    public var loadKey: AnyHashable? {
        get { return ref.loadKey }
        set { mutate { $0.loadKey = newValue } }
    }

    /// Custom info passed alongside the request.
    public var userInfo: Any? {
        get { return ref.userInfo }
        set { mutate { $0.userInfo = newValue } }
    }

    // MARK: Initializers

    /// Initializes a request with the given URL.
    public init(url: URL) {
        ref = Container(resource: Resource.url(url))
        ref.urlString = url.absoluteString
        // creating `.absoluteString` takes 50% of time of Request creation,
        // it's still faster than using URLs as cache keys
    }

    /// Initializes a request with the given request.
    public init(urlRequest: URLRequest) {
        ref = Container(resource: Resource.urlRequest(urlRequest))
        ref.urlString = urlRequest.url?.absoluteString
    }

    #if !os(macOS)

    /// Initializes a request with the given URL.
    /// - parameter processor: Custom image processer.
    public init(url: URL, processors: [ImageProcessing]) {
        self.init(url: url)
        self.processors = processors
    }

    /// Initializes a request with the given request.
    /// - parameter processor: Custom image processer.
    public init(urlRequest: URLRequest, processors: [ImageProcessing]) {
        self.init(urlRequest: urlRequest)
        self.processors = processors
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
        var resource: Resource
        var urlString: String? // memoized absoluteString
        var processors: [ImageProcessing]
        var memoryCacheOptions = MemoryCacheOptions()
        var priority: ImageRequest.Priority = .normal
        var cacheKey: AnyHashable?
        var loadKey: AnyHashable?
        var userInfo: Any?

        /// Creates a resource with a default processor.
        init(resource: Resource) {
            self.resource = resource
            self.processors = [] // TODO: impr perf
        }

        /// Creates a copy.
        init(container ref: Container) {
            self.resource = ref.resource
            self.urlString = ref.urlString
            self.processors = ref.processors
            self.memoryCacheOptions = ref.memoryCacheOptions
            self.priority = ref.priority
            self.cacheKey = ref.cacheKey
            self.loadKey = ref.loadKey
            self.userInfo = ref.userInfo
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

extension ImageRequest {
    // Uniquely identifies a cache processed image.
    struct CacheKey: Hashable {
        let request: ImageRequest

        func hash(into hasher: inout Hasher) {
            if let customKey = request.ref.cacheKey {
                hasher.combine(customKey)
            } else {
                hasher.combine(request.ref.urlString?.hashValue ?? 0)
            }
        }

        static func == (lhs: CacheKey, rhs: CacheKey) -> Bool {
            let lhs = lhs.request.ref, rhs = rhs.request.ref
            if let lhsCustomKey = lhs.cacheKey, let rhsCustomKey = rhs.cacheKey {
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
            if let customKey = request.ref.loadKey {
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
            if let lhsCustomKey = lhs.loadKey, let rhsCustomKey = rhs.loadKey {
                return lhsCustomKey == rhsCustomKey
            }
            return lhs.urlString == rhs.urlString
                && isEqual(lhs.resource.urlRequest, rhs.resource.urlRequest)
        }
    }
}
