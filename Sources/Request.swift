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
                $0._urlString = newValue.url?.absoluteString
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

    /// Returns a key that compares requests with regards to caching images.
    ///
    /// The default key considers two requests equivalent it they have the same
    /// `URLRequests` and the same processors. `URLRequests` are compared
    /// just by their `URLs`.
    public var cacheKey: AnyHashable {
        get { return _ref.cacheKey ?? AnyHashable(CacheKey(request: self)) }
        set { _mutate { $0.cacheKey = newValue } }
    }

    /// Returns a key that compares requests with regards to loading images.
    ///
    /// The default key considers two requests equivalent it they have the same
    /// `URLRequests` and the same processors. `URLRequests` are compared by
    /// their `URL`, `cachePolicy`, and `allowsCellularAccess` properties.
    public var loadKey: AnyHashable {
        get { return _ref.loadKey ?? AnyHashable(LoadKey(request: self)) }
        set { _mutate { $0.loadKey = newValue } }
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
        _ref._urlString = url.absoluteString
        // creating `.absoluteString` takes 50% of time of Request creation,
        // it's still faster than using URLs as cache keys
    }

    /// Initializes a request with the given request.
    public init(urlRequest: URLRequest) {
        _ref = Container(resource: Resource.urlRequest(urlRequest))
        _ref._urlString = urlRequest.url?.absoluteString
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
        var _urlString: String? // memoized absoluteString
        var processor: AnyProcessor? {
            didSet { _isUsingDefaultProcessor = false }
        }
        private var _isUsingDefaultProcessor = true
        var memoryCacheOptions = MemoryCacheOptions()
        var cacheKey: AnyHashable?
        var loadKey: AnyHashable?
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
            self._urlString = ref._urlString
            self.processor = ref.processor
            self._isUsingDefaultProcessor = ref._isUsingDefaultProcessor // order is important here
            self.memoryCacheOptions = ref.memoryCacheOptions
            self.cacheKey = ref.cacheKey
            self.loadKey = ref.loadKey
            self.progress = ref.progress
            self.userInfo = ref.userInfo
        }

        #if !os(macOS)
        private static let decompressor = AnyProcessor(Decompressor())
        #endif

        func isEqualProcessor(to ref: Container) -> Bool {
            return (_isUsingDefaultProcessor && ref._isUsingDefaultProcessor) || processor == ref.processor
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
    private struct CacheKey: Hashable {
        let request: Request

        var hashValue: Int { return request._ref._urlString?.hashValue ?? 0 }

        static func ==(lhs: CacheKey, rhs: CacheKey) -> Bool {
            let lhs = lhs.request, rhs = rhs.request
            return lhs._ref._urlString == rhs._ref._urlString
                && lhs._ref.isEqualProcessor(to: rhs._ref)
        }
    }

    private struct LoadKey: Hashable {
        let request: Request

        var hashValue: Int { return request._ref._urlString?.hashValue ?? 0 }

        static func ==(lhs: LoadKey, rhs: LoadKey) -> Bool {
            func isEqual(_ a: URLRequest, _ b: URLRequest) -> Bool {
                return a.cachePolicy == b.cachePolicy
                    && a.allowsCellularAccess == b.allowsCellularAccess
            }
            let lhs = lhs.request, rhs = rhs.request
            return lhs._ref._urlString == rhs._ref._urlString
                && isEqual(lhs.urlRequest, rhs.urlRequest)
                && lhs._ref.isEqualProcessor(to: rhs._ref)
        }
    }
}
