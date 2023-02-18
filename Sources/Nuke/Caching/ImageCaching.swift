// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

/// In-memory image cache.
///
/// The implementation must be thread safe.
public protocol ImageCaching: AnyObject, Sendable {
    /// Access the image cached for the given request.
    subscript(key: ImageCacheKey) -> ImageContainer? { get set }

    /// Removes all caches items.
    func removeAll()
}

/// An opaque container that acts as a cache key.
///
/// In general, you don't construct it directly, and use ``ImagePipeline`` or ``ImagePipeline/Cache-swift.struct`` APIs.
public struct ImageCacheKey: Hashable, Sendable {
    let key: Inner

    // This is faster than using AnyHashable (and it shows in performance tests).
    enum Inner: Hashable, Sendable {
        case custom(String)
        case `default`(CacheKey)
    }

    public init(key: String) {
        self.key = .custom(key)
    }

    public init(request: ImageRequest) {
        self.key = .default(request.makeImageCacheKey())
    }
}
