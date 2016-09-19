// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Represents an image request.
public struct Request {
    public var urlRequest: URLRequest
    
    public init(url: URL) {
        self.urlRequest = URLRequest(url: url)
    }

    public init(urlRequest: URLRequest) {
        self.urlRequest = urlRequest
    }
    
    #if !os(macOS)
    /// Processor to be applied to the image. `Decompressor` by default.
    public var processor: AnyProcessor? = AnyProcessor(Decompressor())
    #else
    /// Processor to be applied to the image. `nil` by default.
    public var processor: AnyProcessor?
    #endif

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
            $0.urlRequest.url == $1.urlRequest.url && $0.processor == $1.processor
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
            return a.url == b.url &&
                a.cachePolicy == b.cachePolicy &&
                a.allowsCellularAccess == b.allowsCellularAccess
        }
        return request.loadKey ?? AnyHashable(Key(request: request) {
            isEqual($0.urlRequest, $1.urlRequest) && $0.processor == $1.processor
        })
    }
    
    /// Compares two requests for equivalence using an `equator` closure.
    private struct Key: Hashable {
        let request: Request
        let equator: (Request, Request) -> Bool
        
        /// Returns hash from the request's URL.
        var hashValue: Int {
            return request.urlRequest.url?.hashValue ?? 0
        }
        
        /// Compares two keys for equivalence.
        static func ==(lhs: Key, rhs: Key) -> Bool {
            return lhs.equator(lhs.request, rhs.request)
        }
    }
}
