// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Represents an image request.
public struct Request {
    public var urlRequest: URLRequest {
        get { return container.resource.urlRequest }
        set {
            applyMutation {
                $0.resource = Resource.request(newValue)
                $0.urlString = newValue.url?.absoluteString
            }
        }
    }
    
    public init(url: URL) {
        container = Container(resource: Resource.url(url))
        container.urlString = url.absoluteString
    }

    public init(urlRequest: URLRequest) {
        container = Container(resource: Resource.request(urlRequest))
        container.urlString = urlRequest.url?.absoluteString
    }
    
    /// Processor to be applied to the image. `Decompressor` by default.
    public var processor: AnyProcessor? {
        get { return container.processor }
        set { applyMutation { $0.processor = newValue } }
    }
    
    /// The policy to use when dealing with memory cache.
    public struct MemoryCacheOptions {
        /// `true` by default.
        public var readAllowed = true

        /// `true` by default.
        public var writeAllowed = true
        
        public init() {}
    }
    
    /// `MemoryCacheOptions()` by default.
    public var memoryCacheOptions = MemoryCacheOptions()

    /// Returns a key that compares requests with regards to loading images.
    ///
    /// If `nil` default key is used. See `Request.loadKey(for:)` for more info.
    public var loadKey: AnyHashable?

    /// Returns a key that compares requests with regards to caching images.
    ///
    /// If `nil` default key is used. See `Request.cacheKey(for:)` for more info.
    public var cacheKey: AnyHashable?

    /// Custom info passed alongside the request.
    public var userInfo: Any?
    
    
    // everything below exists solely to improve performance
    
    /// Here we implement copy-on-write semantics.
    private mutating func applyMutation(_ block: (Container) -> Void) {
        if !isKnownUniquelyReferenced(&container) {
            container = container.copy()
        }
        block(container)
    }
    
    /// `Request` stores its parameters in a `Container` class to avoid
    /// excessive memberwise retain/release when `Request` is passed around
    /// (and it is passed around **a lot**).
    fileprivate var container: Container
    
    /// Request needs `struct` semantics, but not the way `struct` manages
    /// memory (memberwise retain-release on each copy). This is way `Container`
    /// exists - solely to improve memory performance.
    fileprivate class Container {
        var resource: Resource
        var urlString: String? // memoized absoluteString
        var processor: AnyProcessor?
    
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
            return ref
        }
        
        /// Memoized decompressor
        #if !os(macOS)
        private static let decompressor = AnyProcessor(Decompressor())
        #endif
    }
    
    /// Resource representation (either URL or URLRequest). Only exists to
    /// improve performance by lazily creating requests.
    fileprivate enum Resource {
        case url(URL)
        case request(URLRequest)
        
        var urlRequest: URLRequest {
            switch self {
            case let .url(url): return URLRequest(url: url) // create lazily
            case let .request(request): return request
            }
        }
    }
}

public extension Request {
    /// Appends a processor to the request. You can append arbitrary number of
    /// processors to the request.
    public mutating func process<P: Processing>(with processor: P) {
        if let existing = self.processor {
            // Chain new processor and the existing one.
            self.processor = AnyProcessor(ProcessorComposition([existing, AnyProcessor(processor)]))
        } else {
            self.processor = AnyProcessor(processor)
        }
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
        return request.cacheKey ?? AnyHashable(Key(request: request) {
            $0.container.urlString == $1.container.urlString && $0.processor == $1.processor
        })
    }
    
    /// Returns a key which compares requests with regards to loading images.
    /// Returns `loadKey` if not `nil`. Returns default key otherwise.
    ///
    /// The default key considers two requests equivalent it they have the same
    /// `URLRequests` and the same processors. `URLRequests` are compared by
    /// their `URL`, `cachePolicy`, and `allowsCellularAccess` properties.
    public static func loadKey(for request: Request) -> AnyHashable {
        func isEqual(_ a: URLRequest, _ b: URLRequest) -> Bool {
            return a.cachePolicy == b.cachePolicy && a.allowsCellularAccess == b.allowsCellularAccess
        }
        return request.loadKey ?? AnyHashable(Key(request: request) {
            $0.container.urlString == $1.container.urlString
                && isEqual($0.urlRequest, $1.urlRequest)
                && $0.processor == $1.processor
        })
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
            return request.container.urlString?.hashValue ?? 0
        }
        
        /// Compares two keys for equivalence.
        static func ==(lhs: Key, rhs: Key) -> Bool {
            return lhs.equator(lhs.request, rhs.request)
        }
    }
}
