// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// In-memory image cache.
///
/// - important: The implementation must be thread safe.
public protocol ImageCaching: AnyObject, Sendable {
    /// Access the image cached for the given request.
    subscript(key: ImageCacheKey) -> ImageContainer? { get set }

    /// Removes all cached items.
    func removeAll()
}

/// An opaque container that acts as a memory cache key.
///
/// Typically, you don't construct this directly - use the ``ImagePipeline`` or
/// ``ImagePipeline/Cache-swift.struct`` APIs instead.
public struct ImageCacheKey: Hashable, Sendable {
    let key: Inner

    // This is faster than using AnyHashable (and it shows in performance tests).
    enum Inner: Hashable, Sendable {
        case custom(String)
        case `default`(MemoryCacheKey)
    }

    public init(key: String) {
        self.key = .custom(key)
    }

    public init(request: ImageRequest) {
        self.key = .default(MemoryCacheKey(request))
    }
}
