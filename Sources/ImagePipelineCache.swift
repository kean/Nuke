// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

public extension ImagePipeline {
    /// Thread-safe.
    final class Cache {
        private let configuration: ImagePipeline.Configuration
        private(set) var imageCache: ImageCache?

        init(configuration: ImagePipeline.Configuration) {
            self.configuration = configuration
            if let imageCache = configuration.imageCache as? ImageCache {
                self.imageCache = imageCache
            }
        }

        /// A convenience API that returns processed image from the memory cache
        /// for the given request.
        public subscript(request: ImageRequestConvertible) -> PlatformImage? {
            get {
                cachedImageFromMemoryCache(for: request.asImageRequest())?.image
            }
            set {
                if let image = newValue {
                    storeCachedImageInMemoryCache(ImageContainer(image: image), for: request.asImageRequest())
                } else {
                    removeCachedImageFromMemoryCache(for: request.asImageRequest())
                }
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
        /// - parameter caches: `[.memory]`, by default.
        public func cachedImage(for request: ImageRequest, caches: Caches = [.memory]) -> ImageContainer? {
            if caches.contains(.memory) {
                if let image = cachedImageFromMemoryCache(for: request) {
                    return image
                }
            }
            if caches.contains(.disk) {
                if let data = cachedData(for: request),
                   let image = decodeImageData(data, for: request) {
                    return image
                }
            }
            return nil
        }

        private func cachedImageFromMemoryCache(for request: ImageRequest) -> ImageContainer? {
            guard request.cachePolicy != .reloadIgnoringCachedData && request.options.memoryCacheOptions.isReadAllowed else {
                return nil
            }
            let key = makeMemoryCacheKey(for: request)
            if let imageCache = self.imageCache {
                return imageCache[key] // Fast path for a default cache (no protocol call)
            } else {
                return configuration.imageCache?[key]
            }
        }

        /// Stores the image in the memory cache. Add `.disk` as a source to also
        /// store it in the disk cache (image will be encoded).
        ///
        /// - note: Respects request cache options.
        ///
        /// - note: Default `DiskCache` stores data asynchronously, so it's safe
        /// to call this method even from the main thread.
        ///
        /// - parameter request: The request. Make sure to remove the processors
        /// if you want to retrieve an original image (if it's stored).
        /// - parameter caches: `[.memory]`, by default.
        public func storeCachedImage(_ image: ImageContainer, for request: ImageRequest, caches: Caches = [.memory]) {
            let request = configuration.inheritOptions(request)
            if caches.contains(.memory) {
                storeCachedImageInMemoryCache(image, for: request)
            }
            if caches.contains(.disk) {
                if let data = encodeImage(image, for: request) {
                    storeCachedData(data, for: request)
                }
            }
        }

        private func storeCachedImageInMemoryCache(_ image: ImageContainer, for request: ImageRequest) {
            guard request.options.memoryCacheOptions.isWriteAllowed else {
                return
            }
            guard !image.isPreview || configuration.isStoringPreviewsInMemoryCache else {
                return
            }
            let key = makeMemoryCacheKey(for: request)
            configuration.imageCache?[key] = image
        }

        public func removeCachedImage(for request: ImageRequest, caches: Caches = [.memory]) {
            if caches.contains(.memory) {
                removeCachedImageFromMemoryCache(for: request)
            }
            if caches.contains(.disk) {
                removeCachedData(request: request)
            }
        }

        func removeCachedImageFromMemoryCache(for request: ImageRequest) {
            let key = makeMemoryCacheKey(for: request)
            configuration.imageCache?[key] = nil
        }

        // MARK: Cached Data

        public func cachedData(for request: ImageRequest) -> Data? {
            guard request.cachePolicy != .reloadIgnoringCachedData else {
                return nil
            }
            guard let dataCache = configuration.dataCache else {
                return nil
            }
            let key = makeDiskCacheKey(for: request)
            return dataCache.cachedData(for: key)
        }

        public func storeCachedData(_ data: Data, for request: ImageRequest) {
            guard let dataCache = configuration.dataCache else {
                return
            }
            let key = makeDiskCacheKey(for: request)
            dataCache.storeData(data, for: key)
        }

        public func removeCachedData(request: ImageRequest) {
            guard let dataCache = configuration.dataCache else {
                return
            }
            let key = makeDiskCacheKey(for: request)
            dataCache.removeData(for: key)
        }

        // MARK: Keys

        public func makeMemoryCacheKey(for request: ImageRequest) -> ImageCacheKey {
            ImageCacheKey(request: request)
        }

        public func makeDiskCacheKey(for request: ImageRequest) -> String {
            request.makeCacheKeyForFinalImageData()
        }

        // MARK: Misc

        public func removeAll(caches: Caches = [.all]) {
            if caches.contains(.memory) {
                configuration.imageCache?.removeAll()
            }
            if caches.contains(.disk) {
                configuration.dataCache?.removeAll()
            }
        }

        // MARK: Encode/Decode (Private)

        private func decodeImageData(_ data: Data, for request: ImageRequest) -> ImageContainer? {
            let context = ImageDecodingContext(request: request, data: data, isCompleted: true, urlResponse: nil)
            guard let decoder = configuration.makeImageDecoder(context) else {
                return nil
            }
            return decoder.decode(data, urlResponse: nil, isCompleted: true)?.container
        }

        private func encodeImage(_ image: ImageContainer, for request: ImageRequest) -> Data? {
            let context = ImageEncodingContext(request: request, image: image.image, urlResponse: nil)
            let encoder = configuration.makeImageEncoder(context)
            return encoder.encode(image, context: context)
        }

        // MARK: Options

        public struct Caches: OptionSet {
            public let rawValue: Int
            public init(rawValue: Int) {
                self.rawValue = rawValue
            }

            public static let memory = Caches(rawValue: 1 << 0)
            public static let disk = Caches(rawValue: 1 << 1)
            public static let all: Caches = [.memory, .disk]
        }
    }
}
