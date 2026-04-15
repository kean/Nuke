// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import ImageIO

extension ImagePipeline {
    /// The pipeline configuration.
    public struct Configuration: Sendable {
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

        /// Determines what images are stored in the disk cache (``DataCaching``).
        /// ``ImagePipeline/DataCachePolicy/storeOriginalData`` by default.
        public var dataCachePolicy = ImagePipeline.DataCachePolicy.storeOriginalData

        /// Enables task coalescing. When enabled, the pipeline avoids duplicated
        /// work when loading images. A task is only cancelled when all requests
        /// associated with it are cancelled. The pipeline also automatically
        /// manages the priority of the deduplicated work. `true` by default.
        ///
        /// For example, given these two requests:
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
        /// Nuke loads the image data once, resizes once, and applies the blur
        /// once — no duplicated work at any stage.
        public var isTaskCoalescingEnabled = true

        /// Enables the rate limiter. When enabled, the pipeline throttles requests
        /// to prevent thrashing the underlying systems (e.g. `URLSession`). The
        /// rate limiter only activates when requests are started and cancelled at
        /// a high rate, such as during fast scrolling. `true` by default.
        public var isRateLimiterEnabled = true

        /// Enables progressive decoding. When enabled, the pipeline produces a
        /// new image preview each time it receives a new chunk of data. Whether
        /// a preview is produced depends on the decoder — ``ImageDecoders/Default``
        /// supports progressive JPEG. `false` by default.
        public var isProgressiveDecodingEnabled = false

        /// The minimum interval between progressive decoding attempts, in
        /// seconds. When data arrives faster than this interval, intermediate
        /// chunks are skipped. `0.5` by default.
        public var progressiveDecodingInterval: TimeInterval = 0.5

        /// Stores progressively generated previews in the memory cache. All
        /// previews have ``ImageContainer/isPreview`` set to `true`. `true` by
        /// default.
        public var isStoringPreviewsInMemoryCache = true

        /// If the data task is terminated (either because of a failure or a
        /// cancellation) and the image was partially loaded, the next load will
        /// resume where it left off. Supports both validators (`ETag`,
        /// `Last-Modified`). Resumable downloads are enabled by default.
        public var isResumableDataEnabled = true

        /// If enabled, the pipeline will load the local resources (`file` and
        /// `data` schemes) inline without using the data loader. By default, `true`.
        public var isLocalResourcesSupportEnabled = true

        /// - warning: Deprecated. The automatic downscaling implementation has
        /// been removed. Use ``ImageRequest/ThumbnailOptions`` to control the
        /// decoded image size on a per-request basis instead.
        @available(*, deprecated, message: "Automatic decoded image size limiting has been removed. Use ImageRequest.ThumbnailOptions to control decoded image size per request.")
        public var maximumDecodedImageSize: Int? {
            get { _maximumDecodedImageSize }
            set { _maximumDecodedImageSize = newValue }
        }
        private var _maximumDecodedImageSize: Int?

        /// The maximum response data size in bytes allowed before the download
        /// is automatically cancelled. Downloads that exceed this limit fail
        /// with ``ImagePipeline/Error/dataDownloadExceededMaximumSize``. `nil`
        /// disables the check. The default value is 10% of physical memory,
        /// capped at 200 MB.
        public var maximumResponseDataSize: Int? = {
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            let limit = min(209_715_200 /* 200 MB */, physicalMemory / 10)
            return Int(limit)
        }()

        // MARK: - Options (Shared)

        /// Enables `os_signpost` logging for measuring performance. When enabled,
        /// all performance metrics are visible in the Instruments app. `false`
        /// by default.
        ///
        /// For more information, see the [Logging](https://developer.apple.com/documentation/os/logging)
        /// documentation and [WWDC 2018 Session 405](https://developer.apple.com/videos/play/wwdc2018/405/).
        public static var isSignpostLoggingEnabled: Bool {
            get { _isSignpostLoggingEnabled.value }
            set { _isSignpostLoggingEnabled.value = newValue }
        }

        private static let _isSignpostLoggingEnabled = Mutex(value: false)

        private var isCustomImageCacheProvided = false

        // MARK: - Task Queues

        /// Data loading queue. Default maximum concurrent task count is 6.
        public var dataLoadingQueue = TaskQueue(maxConcurrentOperationCount: 6)

        /// Image decoding queue. Default maximum concurrent task count is 1.
        public var imageDecodingQueue = TaskQueue(maxConcurrentOperationCount: 1)

        /// Image encoding queue. Default maximum concurrent task count is 1.
        public var imageEncodingQueue = TaskQueue(maxConcurrentOperationCount: 1)

        /// Image processing queue. Default maximum concurrent task count is 2.
        public var imageProcessingQueue = TaskQueue(maxConcurrentOperationCount: 2)

        /// Image decompressing queue. Default maximum concurrent task count is 2.
        public var imageDecompressingQueue = TaskQueue(maxConcurrentOperationCount: 2)

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
        /// that adjusts based on the amount of device memory.
        public static var withURLCache: Configuration { Configuration() }

        /// A configuration with an aggressive disk cache (``DataCache``) with a
        /// size limit of 150 MB. An HTTP cache (`URLCache`) is disabled.
        ///
        /// Also uses ``ImageCache/shared`` for in-memory caching with the size
        /// that adjusts based on the amount of device memory.
        public static var withDataCache: Configuration {
            withDataCache()
        }

        /// A configuration with an aggressive disk cache (``DataCache``) with a
        /// size limit of 150 MB by default. An HTTP cache (`URLCache`) is disabled.
        ///
        /// Also uses ``ImageCache/shared`` for in-memory caching with the size
        /// that adjusts based on the amount of device memory.
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
            if let sizeLimit {
                dataCache?.sizeLimit = sizeLimit
            }
            config.dataCache = dataCache

            return config
        }
    }

    /// Determines what images are stored in the disk cache.
    @frozen public enum DataCachePolicy: Sendable {
        /// Store original image data for requests with no processors. Store
        /// _only_ processed images for requests with processors.
        ///
        /// - note: Store only processed images for local resources (file:// or
        /// data:// URL scheme).
        ///
        /// - important: With this policy, the pipeline's ``ImagePipeline/loadData(with:completion:)``
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
        /// - important: With this policy, the pipeline's ``ImagePipeline/loadData(with:completion:)``
        /// method will not store the images in the disk cache – this method only
        /// loads data and doesn't decode images.
        case storeEncodedImages

        /// Stores both processed images and the original image data.
        ///
        /// - note: If the resource is local (has file:// or data:// scheme),
        /// only the processed images are stored.
        case storeAll
    }

    /// Determines how progressive (partial) image previews are generated during
    /// downloads.
    @frozen public enum PreviewPolicy: Sendable, Equatable {
        /// Use Image I/O incremental decoding to produce progressive previews.
        case incremental
        /// Extract the embedded EXIF thumbnail if available, then stop.
        case thumbnail
        /// No previews are generated for partially downloaded data.
        case disabled

        /// Returns the default policy for the given data: `.incremental` for
        /// progressive JPEGs and GIFs, `.disabled` for everything else.
        public static func `default`(for data: Data) -> PreviewPolicy {
            let type = AssetType(data)
            if type == .gif {
                return .incremental
            }
            if type == .jpeg && _isProgressiveJPEG(data) {
                return .incremental
            }
            return .disabled
        }

        private static func _isProgressiveJPEG(_ data: Data) -> Bool {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let jfif = properties[kCGImagePropertyJFIFDictionary] as? [CFString: Any],
                  let isProgressive = jfif[kCGImagePropertyJFIFIsProgressive] as? Bool else {
                return false
            }
            return isProgressive
        }
    }
}
