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

// MARK: - RequestEquating

/// Tests requests for equivalence in various contexts (caching, loading, etc).
public protocol RequestEquating {
    func isEqual(_ a: Request, to b: Request) -> Bool
}

/// Considers two requests equivalent it they have the same `URLRequests` and
/// the same processors. `URLRequests` are compared by their `URL`, `cachePolicy`,
/// and `allowsCellularAccess` properties. To change this behaviour just create
/// a new `RequestEquating` type.
public struct RequestLoadingEquator: RequestEquating {
    public init() {}
    
    public func isEqual(_ a: Request, to b: Request) -> Bool {
        return isEqual(a.urlRequest, to: b.urlRequest) && a.processor == b.processor
    }
    
    private func isEqual(_ a: URLRequest, to b: URLRequest) -> Bool {
        return a.url == b.url &&
            a.cachePolicy == b.cachePolicy &&
            a.allowsCellularAccess == b.allowsCellularAccess
    }
}

/// Considers two requests equivalent it they have the same `URLRequests` and
/// the same processors. `URLRequests` are compared just by their `URLs`.
/// To change this behaviour just create a new `RequestEquating` type.
public struct RequestCachingEquator: RequestEquating {
    public init() {}
    
    public func isEqual(_ a: Request, to b: Request) -> Bool {
        return a.urlRequest.url == b.urlRequest.url && a.processor == b.processor
    }
}

// MARK: - RequestKey

/// Makes it possible to use Request as a key.
internal final class RequestKey: NSObject {
    private let request: Request
    private let equator: RequestEquating
    
    init(_ request: Request, equator: RequestEquating) {
        self.request = request
        self.equator = equator
    }
    
    /// Returns hash from the request's URL.
    override var hash: Int {
        return request.urlRequest.url?.hashValue ?? 0
    }

    /// Compares two keys for equivalence using one of their equators.
    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? RequestKey else { return false }
        return equator.isEqual(request, to: object.request)
    }
}
