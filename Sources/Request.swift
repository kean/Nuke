// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Represents an image request.
public struct Request {
    public var urlRequest: URLRequest
    
    /// Initializes `Request` with the URL.
    public init(url: URL) {
        self.urlRequest = URLRequest(url: url)
    }
    
    /// Initializes `Request` with the URL request.
    public init(urlRequest: URLRequest) {
        self.urlRequest = urlRequest
    }
    
    /// Processors to be applied to the image. Empty by default.
    public var processors = [AnyProcessor]()

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

    /// Returns key which compares requests with regards to loading images.
    ///
    /// If `nil` default key is used. `nil` by default.
    public var loadKey: AnyHashable?

    /// Returns key which compares requests with regards to cachings images.
    ///
    /// If `nil` default key is used. `nil` by default.
    public var cacheKey: AnyHashable?

    /// Allows you to pass custom info alongside the request.
    public var userInfo: Any?
}

public extension Request {
    /// Adds a processor to the request.
    public func process<P: Processing>(with processor: P) -> Request {
        var request = self
        request.processors.append(AnyProcessor(processor))
        return request
    }
    
    /// Wraps processors into ProcessorComposition.
    internal var processor: ProcessorComposition? {
        return processors.isEmpty ? nil : ProcessorComposition(processors: processors)
    }
}

public extension Request {
    /// Returns key which compares requests with regards to cachings images.
    /// Returns `cacheKey` if not nil. Returns default key otherwise.
    ///
    /// The default key considers two requests equivalent it they have the same
    /// `URLRequests` and the same processors. `URLRequests` are compared
    /// just by their `URLs`.
    public static func cacheKey(for request: Request) -> AnyHashable {
        return request.cacheKey ?? AnyHashable(RequestKey(request: request) {
            $0.urlRequest.url == $0.urlRequest.url && $1.processor == $1.processor
        })
    }
    
    /// Returns key which compares requests with regards to loading images.
    /// Returns `loadKey` if not nil. Returns default key otherwise.
    ///
    /// The default key considers two requests equivalent it they have the same
    /// `URLRequests` and the same processors. `URLRequests` are compared by
    /// their `URL`, `cachePolicy`, and `allowsCellularAccess` properties.
    public static func loadKey(for request: Request) -> AnyHashable {
        func isEqual(_ a: URLRequest, to b: URLRequest) -> Bool {
            return a.url == b.url &&
                a.cachePolicy == b.cachePolicy &&
                a.allowsCellularAccess == b.allowsCellularAccess
        }
        return request.loadKey ?? AnyHashable(RequestKey(request: request) {
            isEqual($0.urlRequest, to: $1.urlRequest) && $0.processor == $1.processor
        })
    }
}

/// Compares two requests for equivalence using an `equator` closure.
private struct RequestKey: Hashable {
    let request: Request
    let equator: (Request, Request) -> Bool
    
    /// Returns hash from the request's URL.
    var hashValue: Int {
        return request.urlRequest.url?.hashValue ?? 0
    }
    
    /// Compares two keys for equivalence.
    static func ==(lhs: RequestKey, rhs: RequestKey) -> Bool {
        return lhs.equator(lhs.request, rhs.request)
    }
}
