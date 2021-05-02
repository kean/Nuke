// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

public extension ImagePipeline {
    /// Thread-safe.
    struct Cache {
        let pipeline: ImagePipeline

        /// Returns processed image from the memory cache for the given request.
        public subscript(request: ImageRequestConvertible) -> PlatformImage? {
            get {
                cachedImageFromMemoryCache(for: request.asImageRequest())?.image
            }
            set {
                fatalError("Not implemented")
            }
        }

        // MARK: Cached Images

        /// Returns a cached image from the memory cache. Add `.disk` as a source
        /// to also check the disk cache.
        ///
        /// - note: Respects request options such as `cachePolicy`.
        ///
        /// - parameter request: The request. Make sure to remove the processors
        /// if you want to retrieve an original image (if it's stored).
        /// - parameter sources: `[.memory]`, by default.
        public func cachedImage(for request: ImageRequest, sources: Set<ImageCacheType> = [.memory]) -> ImageContainer? {
            if sources.contains(.memory) {
                if let image = cachedImageFromMemoryCache(for: request) {
                    return image
                }
            }
            if sources.contains(.disk) {
                if let data = cachedData(for: request),
                   let image = decodeImageData(data, for: request) {
                    return image
                }
            }
            return nil
        }

        func cachedImageFromMemoryCache(for request: ImageRequest) -> ImageContainer? {
            guard request.cachePolicy != .reloadIgnoringCachedData && request.options.memoryCacheOptions.isReadAllowed else {
                return nil
            }
            let request = pipeline.inheritOptions(request)
            let key = makeMemoryCacheKey(for: request)
            if let imageCache = pipeline.imageCache {
                return imageCache[key] // Fast path for a default cache (no protocol call)
            } else {
                return pipeline.configuration.imageCache?[key]
            }
        }

        func decodeImageData(_ data: Data, for request: ImageRequest) -> ImageContainer? {
            let context = ImageDecodingContext(request: request, data: data, isCompleted: true, urlResponse: nil)
            guard let decoder = pipeline.configuration.makeImageDecoder(context) else {
                return nil
            }
            return decoder.decode(data, urlResponse: nil, isCompleted: true)?.container
        }

        public func storeCachedImage(_ container: ImageContainer, for request: ImageRequest, sources: Set<ImageCacheType> = [.memory, .disk]) {
            fatalError("Not implemented")
        }

        public func removeCachedImage(for request: ImageRequest, sources: Set<ImageCacheType> = [.memory, .disk]) {
            fatalError("Not implemented")
        }

        // MARK: Cached Data

        #warning("Should it also work for a URL cache?")
        public func cachedData(for request: ImageRequest) -> Data? {
            guard request.cachePolicy != .reloadIgnoringCachedData else {
                return nil
            }
            guard let dataCache = pipeline.configuration.dataCache else {
                return nil
            }
            let key = makeDiskCacheKey(for: request)
            return dataCache.cachedData(for: key)
        }

        public func storeCachedData(_ data: Data, for request: ImageRequest) {
            fatalError("Not implemented")
        }

        public func removeCachedData(request: ImageRequest) {
            fatalError("Not implemented")
        }

        // MARK: Keys

        public func makeMemoryCacheKey(for request: ImageRequest) -> ImageCacheKey {
            ImageCacheKey(request: request)
        }

        public func makeDiskCacheKey(for request: ImageRequest) -> String {
            request.makeCacheKeyForFinalImageData()
        }

        // MARK: Misc

        public func removeAll(sources: Set<ImageCacheType> = [.memory, .disk]) {
            fatalError("Not implemented")
        }
    }
}

public enum ImageCacheType {
    case memory
    case disk
}
