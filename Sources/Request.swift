// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation

#if !os(macOS)
    import UIKit
#endif

/// Represents an image request.
public struct Request {
    
    // MARK: Parameters of the Request

    /// The `URLRequest` used for loading an image.
    public var urlRequest: URLRequest {
        get { return _ref.resource.urlRequest }
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
        get { return _ref.processor }
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
    public var memoryCacheOptions: MemoryCacheOptions {
        get { return _ref.memoryCacheOptions }
        set { _mutate { $0.memoryCacheOptions = newValue } }
    }

    /// Returns a key that compares requests with regards to loading images.
    ///
    /// If `nil` default key is used. See `Request.loadKey(for:)` for more info.
    public var loadKey: AnyHashable? {
        get { return _ref.loadKey }
        set { _mutate { $0.loadKey = newValue } }
    }

    /// Returns a key that compares requests with regards to caching images.
    ///
    /// If `nil` default key is used. See `Request.cacheKey(for:)` for more info.
    public var cacheKey: AnyHashable? {
        get { return _ref.cacheKey }
        set { _mutate { $0.cacheKey = newValue } }
    }

    /// The closure that is executed periodically on the main thread to report
    /// the progress of the request. `nil` by default.
    public var progress: ProgressHandler? {
        get { return _ref.progress }
        set { _mutate { $0.progress = newValue }}
    }

    /// Custom info passed alongside the request.
    public var userInfo: Any? {
        get { return _ref.userInfo }
        set { _mutate { $0.userInfo = newValue }}
    }


    // MARK: Initializers

    /// Initializes a request with the given URL.
    public init(url: URL) {
        _ref = Container(resource: Resource.url(url))
        _ref.urlString = url.absoluteString
    }

    /// Initializes a request with the given request.
    public init(urlRequest: URLRequest) {
        _ref = Container(resource: Resource.urlRequest(urlRequest))
        _ref.urlString = urlRequest.url?.absoluteString
    }

    #if !os(macOS)

    // Convenience initializers with `targetSize` and `contentMode`. The reason
    // why those are implemented as separate init methods is to take advantage
    // of memorized `decompressor` when custom parameters are not needed.

    /// Initializes a request with the given URL.
    /// - parameter targetSize: Size in pixels.
    /// - parameter contentMode: An option for how to resize the image
    /// to the target size.
    public init(url: URL, targetSize: CGSize, contentMode: Decompressor.ContentMode) {
        self = Request(url: url)
        _ref.processor = AnyProcessor(Decompressor(targetSize: targetSize, contentMode: contentMode))
    }

    /// Initializes a request with the given request.
    /// - parameter targetSize: Size in pixels.
    /// - parameter contentMode: An option for how to resize the image
    /// to the target size.
    public init(urlRequest: URLRequest, targetSize: CGSize, contentMode: Decompressor.ContentMode) {
        self = Request(urlRequest: urlRequest)
        _ref.processor = AnyProcessor(Decompressor(targetSize: targetSize, contentMode: contentMode))
    }

    #endif

    // CoW:

    private var _ref: Container

    private mutating func _mutate(_ closure: (Container) -> Void) {
        if !isKnownUniquelyReferenced(&_ref) {
            _ref = Container(container: _ref)
        }
        closure(_ref)
    }

    /// Just like many Swift built-in types, `Request` uses CoW approach to
    /// avoid memberwise retain/releases when `Request is passed around.
    private class Container {
        var resource: Resource
        var urlString: String? // memoized absoluteString
        var processor: AnyProcessor?
        var memoryCacheOptions = MemoryCacheOptions()
        var loadKey: AnyHashable?
        var cacheKey: AnyHashable?
        var progress: ProgressHandler?
        var userInfo: Any?

        /// Creates a resource with a default processor.
        init(resource: Resource) {
            self.resource = resource

            #if !os(macOS)
            // set default processor
            self.processor = Container.decompressor
            #endif
        }

        /// Creates a copy.
        init(container ref: Container) {
            self.resource = ref.resource
            self.urlString = ref.urlString
            self.processor = ref.processor
            self.memoryCacheOptions = ref.memoryCacheOptions
            self.loadKey = ref.loadKey
            self.cacheKey = ref.cacheKey
            self.progress = ref.progress
            self.userInfo = ref.userInfo
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

    /// Appends a processor to the request. You can append arbitrary number of
    /// processors to the request.
    public mutating func process<Key: Hashable>(key: Key, _ closure: @escaping (Image) -> Image?) {
        process(with: AnonymousProcessor(key, closure))
    }

    /// Appends a processor to the request. You can append arbitrary number of
    /// processors to the request.
    public func processed<Key: Hashable>(key: Key, _ closure: @escaping (Image) -> Image?) -> Request {
        return processed(with: AnonymousProcessor(key, closure))
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
            $0._ref.urlString == $1._ref.urlString && $0.processor == $1.processor
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
            $0._ref.urlString == $1._ref.urlString
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
            return request._ref.urlString?.hashValue ?? 0
        }

        /// Compares two keys for equivalence.
        static func ==(lhs: Key, rhs: Key) -> Bool {
            return lhs.equator(lhs.request, rhs.request)
        }
    }
}
