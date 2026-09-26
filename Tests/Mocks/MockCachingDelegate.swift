// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

/// Overrides the caching hooks of ``ImagePipeline/Delegate-swift.protocol``
/// with closures, falling back to the pipeline configuration for the ones
/// that are not set, and records the `willCache` calls.
final class MockCachingDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    struct WillCacheCall {
        let data: Data
        let image: ImageContainer?
        let request: ImageRequest
    }

    var imageCache: ((ImageRequest) -> (any ImageCaching)?)? {
        get { lock.withLock { _imageCache } }
        set { lock.withLock { _imageCache = newValue } }
    }
    var dataCache: ((ImageRequest) -> (any DataCaching)?)? {
        get { lock.withLock { _dataCache } }
        set { lock.withLock { _dataCache = newValue } }
    }
    var cacheKey: ((ImageRequest) -> String?)? {
        get { lock.withLock { _cacheKey } }
        set { lock.withLock { _cacheKey = newValue } }
    }
    var decoder: ((ImageDecodingContext) -> (any ImageDecoding)?)? {
        get { lock.withLock { _decoder } }
        set { lock.withLock { _decoder = newValue } }
    }
    var encoder: ((ImageEncodingContext) -> any ImageEncoding)? {
        get { lock.withLock { _encoder } }
        set { lock.withLock { _encoder = newValue } }
    }
    /// Replaces the data passed to `willCache`. Return `nil` to prevent
    /// caching.
    var willCacheTransform: ((Data) -> Data?)? {
        get { lock.withLock { _willCacheTransform } }
        set { lock.withLock { _willCacheTransform = newValue } }
    }

    var willCacheCalls: [WillCacheCall] { lock.withLock { _willCacheCalls } }

    // The test sets the hooks, and the pipeline calls them from its own
    // threads.
    private let lock = NSLock()
    private var _imageCache: ((ImageRequest) -> (any ImageCaching)?)?
    private var _dataCache: ((ImageRequest) -> (any DataCaching)?)?
    private var _cacheKey: ((ImageRequest) -> String?)?
    private var _decoder: ((ImageDecodingContext) -> (any ImageDecoding)?)?
    private var _encoder: ((ImageEncodingContext) -> any ImageEncoding)?
    private var _willCacheTransform: ((Data) -> Data?)?
    private var _willCacheCalls: [WillCacheCall] = []

    func imageCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any ImageCaching)? {
        if let imageCache { return imageCache(request) }
        return pipeline.configuration.imageCache
    }

    func dataCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any DataCaching)? {
        if let dataCache { return dataCache(request) }
        return pipeline.configuration.dataCache
    }

    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        cacheKey?(request)
    }

    func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> (any ImageDecoding)? {
        if let decoder { return decoder(context) }
        return pipeline.configuration.makeImageDecoder(context)
    }

    func imageEncoder(for context: ImageEncodingContext, pipeline: ImagePipeline) -> any ImageEncoding {
        if let encoder { return encoder(context) }
        return pipeline.configuration.makeImageEncoder(context)
    }

    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline) async -> Data? {
        lock.withLock { _willCacheCalls.append(WillCacheCall(data: data, image: image, request: request)) }
        return willCacheTransform.map { $0(data) } ?? data
    }
}
