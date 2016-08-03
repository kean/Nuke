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
    
    /// Convenience method for adding processors to the `Request`.
    public mutating func add<P: Processing>(processor: P) {
        processors.append(AnyProcessor(processor))
    }
    
    internal var processor: ProcessorComposition? {
        return processors.isEmpty ? nil : ProcessorComposition(processors: processors)
    }
    
    /// A set of options affecting how `Loading` object interacts with its memory cache.
    public struct MemoryCacheOptions {
        public var readAllowed = true
        
        /// Specifies whether loaded object should be stored into memory cache.
        /// `true` by default.
        public var writeAllowed = true
        
        public init() {}
    }
    
    /// `MemoryCacheOptions` by default.
    public var memoryCacheOptions = MemoryCacheOptions()

    /// Allows you to pass custom info alongside the request.
    public var userInfo: Any?
}

// MARK: - RequestEquating

/// Compares two requests for equivalence in different contexts (caching,
/// loading, etc).
public protocol RequestEquating {
    func isEqual(_ a: Request, to b: Request) -> Bool
}

/// Considers two requests equivalent it they have the same `URLRequests` and
/// the same processors. `URLRequests` are compared just by their `URLs`.
/// To customize this behaviour just create a new `RequestEquating` type.
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
/// To customize this behaviour just create a new `RequestEquating` type.
public struct RequestCachingEquator: RequestEquating {
    public init() {}
    
    public func isEqual(_ a: Request, to b: Request) -> Bool {
        return a.urlRequest.url == b.urlRequest.url && a.processor == b.processor
    }
}

// MARK: - RequestKey

/// Makes it possible to use Request as a key.
internal struct RequestKey: Hashable {
    private let request: Request
    private let equator: RequestEquating
    
    init(_ request: Request, equator: RequestEquating) {
        self.request = request
        self.equator = equator
    }
    
    /// Returns hash from the request's URL.
    var hashValue: Int {
        return request.urlRequest.url?.hashValue ?? 0
    }
    
    /// Compares two keys for equivalence.
    static func ==(lhs: RequestKey, rhs: RequestKey) -> Bool {
        return lhs.equator.isEqual(lhs.request, to: rhs.request)
    }
}
