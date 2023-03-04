// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImagePipeline {
    /// The pipeline configuration.
    public struct Configuration: @unchecked Sendable {
        // MARK: - Dependencies

        /// Data loader used by the pipeline.
        public var dataLoader: any DataLoading

        /// Data cache used by the pipeline.
        public var dataCache: (any DataCaching)?

        /// Image cache used by the pipeline.
        public var imageCache: (any ImageCaching)? {
            // This exists simply to ensure we don't init ImageCache.shared if the
            // user provides their own instance.
            get { isCustomImageCacheProvided ? customImageCache : ImageCache.shared }
            set {
                customImageCache = newValue
                isCustomImageCacheProvided = true
            }
        }
        private var customImageCache: (any ImageCaching)?

        /// Default implementation uses shared ``ImageDecoderRegistry`` to create
        /// a decoder that matches the context.
        public var makeImageDecoder: @Sendable (ImageDecodingContext) -> (any ImageDecoding)? = {
            ImageDecoderRegistry.shared.decoder(for: $0)
        }

        /// Returns `ImageEncoders.Default()` by default.
        public var makeImageEncoder: @Sendable (ImageEncodingContext) -> any ImageEncoding = { _ in
            ImageEncoders.Default()
        }

        // MARK: - Options

        /// Decompresses the loaded images. By default, enabled on all platforms
        /// except for `macOS`.
        ///
        /// Decompressing compressed image formats (such as JPEG) can significantly
        /// improve drawing performance as it allows a bitmap representation to be
        /// created in a background rather than on the main thread.
        public var isDecompressionEnabled: Bool {
            get { _isDecompressionEnabled }
            set { _isDecompressionEnabled = newValue }
        }

        /// Set this to `true` to use native `preparingForDisplay()` method for
        /// decompression on iOS and tvOS 15.0 and later. Disabled by default.
        /// If disabled, CoreGraphics-based decompression is used.
        public var isUsingPrepareForDisplay: Bool = false

#if os(macOS)
        var _isDecompressionEnabled = false
#else
        var _isDecompressionEnabled = true
#endif

        /// If you use an aggressive disk cache ``DataCaching``, you can specify
        /// a cache policy with multiple available options and
        /// ``ImagePipeline/DataCachePolicy/storeOriginalData`` used by default.
        public var dataCachePolicy = ImagePipeline.DataCachePolicy.storeOriginalData

        /// `true` by default. If `true` the pipeline avoids duplicated work when
        /// loading images. The work only gets cancelled when all the registered
        /// requests are. The pipeline also automatically manages the priority of the
        /// deduplicated work.
        ///
        /// Let's take these two requests for example:
        ///
        /// ```swift
        /// let url = URL(string: "http://example.com/image")
        /// pipeline.loadImage(with: ImageRequest(url: url, processors: [
        ///     .resize(size: CGSize(width: 44, height: 44)),
        ///     .gaussianBlur(radius: 8)
        /// ]))
        /// pipeline.loadImage(with: ImageRequest(url: url, processors: [
        ///     .resize(size: CGSize(width: 44, height: 44))
        /// ]))
        /// ```
        ///
        /// Nuke will load the image data only once, resize the image once and
        /// apply the blur also only once. There is no duplicated work done at
        /// any stage.
        public var isTaskCoalescingEnabled = true

        /// `true` by default. If `true` the pipeline will rate limit requests
        /// to prevent trashing of the underlying systems (e.g. `URLSession`).
        /// The rate limiter only comes into play when the requests are started
        /// and cancelled at a high rate (e.g. scrolling through a collection view).
        public var isRateLimiterEnabled = true

        /// `false` by default. If `true` the pipeline will try to produce a new
        /// image each time it receives a new portion of data from data loader.
        /// The decoder used by the image loading session determines whether
        /// to produce a partial image or not. The default image decoder
        /// ``ImageDecoders/Default`` supports progressive JPEG decoding.
        public var isProgressiveDecodingEnabled = false

        /// `true` by default. If `true`, the pipeline will store all of the
        /// progressively generated previews in the memory cache. All of the
        /// previews have ``ImageContainer/isPreview`` flag set to `true`.
        public var isStoringPreviewsInMemoryCache = true

        /// If the data task is terminated (either because of a failure or a
        /// cancellation) and the image was partially loaded, the next load will
        /// resume where it left off. Supports both validators (`ETag`,
        /// `Last-Modified`). Resumable downloads are enabled by default.
        public var isResumableDataEnabled = true

        /// A queue on which all callbacks, like `progress` and `completion`
        /// callbacks are called. `.main` by default.
        public var callbackQueue = DispatchQueue.main

        // MARK: - Options (Shared)

        /// `false` by default. If `true`, enables `os_signpost` logging for
        /// measuring performance. You can visually see all the performance
        /// metrics in `os_signpost` Instrument. For more information see
        /// https://developer.apple.com/documentation/os/logging and
        /// https://developer.apple.com/videos/play/wwdc2018/405/.
        public static var isSignpostLoggingEnabled = false

        private var isCustomImageCacheProvided = false

        var debugIsSyncImageEncoding = false

        // MARK: - Operation Queues

        /// Data loading queue. Default maximum concurrent task count is 6.
        public var dataLoadingQueue = OperationQueue(maxConcurrentCount: 6)

        /// Data caching queue. Default maximum concurrent task count is 2.
        public var dataCachingQueue = OperationQueue(maxConcurrentCount: 2)

        /// Image decoding queue. Default maximum concurrent task count is 1.
        public var imageDecodingQueue = OperationQueue(maxConcurrentCount: 1)

        /// Image encoding queue. Default maximum concurrent task count is 1.
        public var imageEncodingQueue = OperationQueue(maxConcurrentCount: 1)

        /// Image processing queue. Default maximum concurrent task count is 2.
        public var imageProcessingQueue = OperationQueue(maxConcurrentCount: 2)

        /// Image decompressing queue. Default maximum concurrent task count is 2.
        public var imageDecompressingQueue = OperationQueue(maxConcurrentCount: 2)

        // MARK: - Initializer

        /// Instantiates a pipeline configuration.
        ///
        /// - parameter dataLoader: `DataLoader()` by default.
        public init(dataLoader: any DataLoading = DataLoader()) {
            self.dataLoader = dataLoader
        }

        // MARK: - Predefined Configurations

        /// A configuration with an HTTP disk cache (`URLCache`) with a size limit
        /// of 150 MB. This is a default configuration.
        ///
        /// Also uses ``ImageCache/shared`` for in-memory caching with the size
        /// that adjusts bsed on the amount of device memory.
        public static var withURLCache: Configuration { Configuration() }

        /// A configuration with an aggressive disk cache (``DataCache``) with a
        /// size limit of 150 MB. An HTTP cache (`URLCache`) is disabled.
        ///
        /// Also uses ``ImageCache/shared`` for in-memory caching with the size
        /// that adjusts bsed on the amount of device memory.
        public static var withDataCache: Configuration {
            withDataCache()
        }

        /// A configuration with an aggressive disk cache (``DataCache``) with a
        /// size limit of 150 MB by default. An HTTP cache (`URLCache`) is disabled.
        ///
        /// Also uses ``ImageCache/shared`` for in-memory caching with the size
        /// that adjusts bsed on the amount of device memory.
        ///
        /// - parameters:
        ///   - name: Data cache name.
        ///   - sizeLimit: Size limit, by default 150 MB.
        public static func withDataCache(
            name: String = "com.github.kean.Nuke.DataCache",
            sizeLimit: Int? = nil
        ) -> Configuration {
            let dataLoader: DataLoader = {
                let config = URLSessionConfiguration.default
                config.urlCache = nil
                return DataLoader(configuration: config)
            }()

            var config = Configuration()
            config.dataLoader = dataLoader

            let dataCache = try? DataCache(name: name)
            if let sizeLimit = sizeLimit {
                dataCache?.sizeLimit = sizeLimit
            }
            config.dataCache = dataCache

            return config
        }
    }

    /// Determines what images are stored in the disk cache.
    public enum DataCachePolicy: Sendable {
        /// Store original image data for requests with no processors. Store
        /// _only_ processed images for requests with processors.
        ///
        /// - note: Store only processed images for local resources (file:// or
        /// data:// URL scheme).
        ///
        /// - important: With this policy, the pipeline's ``ImagePipeline/loadData(with:completion:)-6cwk3``
        /// method will not store the images in the disk cache for requests with
        /// any processors applied – this method only loads data and doesn't
        /// decode images.
        case automatic

        /// Store only original image data.
        ///
        /// - note: If the resource is local (file:// or data:// URL scheme),
        /// data isn't stored.
        case storeOriginalData

        /// Encode and store images.
        ///
        /// - note: This is useful if you want to store images in a format
        /// different than provided by a server, e.g. decompressed. In other
        /// scenarios, consider using ``automatic`` policy instead.
        ///
        /// - important: With this policy, the pipeline's ``ImagePipeline/loadData(with:completion:)-6cwk3``
        /// method will not store the images in the disk cache – this method only
        /// loads data and doesn't decode images.
        case storeEncodedImages

        /// Stores both processed images and the original image data.
        ///
        /// - note: If the resource is local (has file:// or data:// scheme),
        /// only the processed images are stored.
        case storeAll
    }
}
