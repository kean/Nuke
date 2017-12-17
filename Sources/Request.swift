// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Represents an image request.
public struct Request {
    
    // MARK: Parameters of the Request

    /// The `URLRequest` used for loading an image.
    public var urlRequest: URLRequest {
        get { return _container.resource.urlRequest }
        set {
            _mutate {
                $0.resource = Resource.urlRequest(newValue)
                $0.urlString = newValue.url?.absoluteString
            }
        }
    }

    /// Processor to be applied to the image. `Decompressor` by default.
    ///
    /// Decompressing compressed image formats (such as JPEG) can significantly
    /// improve drawing performance as it allows a bitmap representation to be
    /// created in a background rather than on the main thread.
    public var processor: AnyProcessor? {
        get { return _container.processor }
        set { _mutate { $0.processor = newValue } }
    }

    /// The policy to use when reading or writing images to the memory cache.
    public struct MemoryCacheOptions {
        /// `true` by default.
        public var readAllowed = true

        /// `true` by default.
        public var writeAllowed = true

        public init() {}
    }

    /// `MemoryCacheOptions()` (read allowed, write allowed) by default.
    public var memoryCacheOptions = MemoryCacheOptions()

    /// Returns a key that compares requests with regards to loading images.
    ///
    /// If `nil` default key is used. See `Request.loadKey(for:)` for more info.
    public var loadKey: AnyHashable?

    /// Returns a key that compares requests with regards to caching images.
    ///
    /// If `nil` default key is used. See `Request.cacheKey(for:)` for more info.
    public var cacheKey: AnyHashable?

    /// The closure that is executed periodically on the main thread to report
    /// the progress of the request. `nil` by default.
    public var progress: ProgressHandler? {
        get { return _container.progress }
        set { _mutate { $0.progress = newValue }}
    }

    /// Custom info passed alongside the request.
    public var userInfo: Any?


    // MARK: Initializers

    /// Initializes a request with the given URL.
    public init(url: URL) {
        _container = Container(resource: Resource.url(url))
        _container.urlString = url.absoluteString
    }

    /// Initializes a request with the given request.
    public init(urlRequest: URLRequest) {
        _container = Container(resource: Resource.urlRequest(urlRequest))
        _container.urlString = urlRequest.url?.absoluteString
    }

    
    // CoW:

    private var _container: Container

    private mutating func _mutate(_ closure: (Container) -> Void) {
        if !isKnownUniquelyReferenced(&_container) {
            _container = _container.copy()
        }
        closure(_container)
    }

    /// Just like many Swift built-in types, `Request` uses CoW approach to
    /// avoid memberwise retain/releases when `Request is passed around.
    private class Container {
        var resource: Resource
        var urlString: String? // memoized absoluteString
        var processor: AnyProcessor?
        var progress: ProgressHandler?

        init(resource: Resource) {
            self.resource = resource

            #if !os(macOS)
            self.processor = Container.decompressor
            #endif
        }

        func copy() -> Container {
            let ref = Container(resource: resource)
            ref.urlString = urlString
            ref.processor = processor
            ref.progress = progress
            return ref
        }

        #if !os(macOS)
        private static let decompressor = AnyProcessor(Decompressor())
        #endif
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

public extension Request {
    /// Appends a processor to the request. You can append arbitrary number of
    /// processors to the request.
    public mutating func process<P: Processing>(with processor: P) {
        guard let existing = self.processor else {
            self.processor = AnyProcessor(processor); return
        }
        // Chain new processor and the existing one.
        self.processor = AnyProcessor(ProcessorComposition([existing, AnyProcessor(processor)]))
    }

    /// Appends a processor to the request. You can append arbitrary number of
    /// processors to the request.
    public func processed<P: Processing>(with processor: P) -> Request {
        var request = self
        request.process(with: processor)
        return request
    }
}

public extension Request {
    /// Returns a key which compares requests with regards to caching images.
    /// Returns `cacheKey` if not `nil`. Returns default key otherwise.
    ///
    /// The default key considers two requests equivalent it they have the same
    /// `URLRequests` and the same processors. `URLRequests` are compared
    /// just by their `URLs`.
    public static func cacheKey(for request: Request) -> AnyHashable {
        return request.cacheKey ?? AnyHashable(makeCacheKey(request))
    }
    
    private static func makeCacheKey(_ request: Request) -> Key {
        return Key(request: request) {
            $0._container.urlString == $1._container.urlString && $0.processor == $1.processor
        }
    }

    /// Returns a key which compares requests with regards to loading images.
    /// Returns `loadKey` if not `nil`. Returns default key otherwise.
    ///
    /// The default key considers two requests equivalent it they have the same
    /// `URLRequests` and the same processors. `URLRequests` are compared by
    /// their `URL`, `cachePolicy`, and `allowsCellularAccess` properties.
    public static func loadKey(for request: Request) -> AnyHashable {
        return request.loadKey ?? AnyHashable(makeLoadKey(request))
    }
    
    private static func makeLoadKey(_ request: Request) -> Key {
        func isEqual(_ a: URLRequest, _ b: URLRequest) -> Bool {
            return a.cachePolicy == b.cachePolicy && a.allowsCellularAccess == b.allowsCellularAccess
        }
        return Key(request: request) {
            $0._container.urlString == $1._container.urlString
                && isEqual($0.urlRequest, $1.urlRequest)
                && $0.processor == $1.processor
        }
    }

    /// Compares two requests for equivalence using an `equator` closure.
    private class Key: Hashable {
        let request: Request
        let equator: (Request, Request) -> Bool

        init(request: Request, equator: @escaping (Request, Request) -> Bool) {
            self.request = request
            self.equator = equator
        }

        /// Returns hash from the request's URL.
        var hashValue: Int {
            return request._container.urlString?.hashValue ?? 0
        }

        /// Compares two keys for equivalence.
        static func ==(lhs: Key, rhs: Key) -> Bool {
            return lhs.equator(lhs.request, rhs.request)
        }
    }
}
