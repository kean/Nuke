// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

// MARK: - ImagePipeline.Configuration

extension ImagePipeline {
    public struct Configuration {
        // MARK: - Dependencies

        /// Image cache used by the pipeline.
        public var imageCache: ImageCaching? {
            // This exists simply to ensure we don't init ImageCache.shared if the
            // user provides their own instance.
            get {
                isCustomImageCacheProvided ? customImageCache : ImageCache.shared
            }
            set {
                customImageCache = newValue
                isCustomImageCacheProvided = true
            }
        }
        private var customImageCache: ImageCaching?
        private var isCustomImageCacheProvided = false

        /// Data loader used by the pipeline.
        public var dataLoader: DataLoading

        /// Data cache used by the pipeline.
        public var dataCache: DataCaching?

        /// Default implementation uses shared `ImageDecoderRegistry` to create
        /// a decoder that matches the context.
        public var makeImageDecoder: (ImageDecodingContext) -> ImageDecoding? = ImageDecoderRegistry.shared.decoder(for:)

        /// Returns `ImageEncoders.Default()` by default.
        public var makeImageEncoder: (ImageEncodingContext) -> ImageEncoding = { _ in
            ImageEncoders.Default()
        }

        // MARK: - Operation Queues

        /// Data loading queue. Default maximum concurrent task count is 6.
        public var dataLoadingQueue = OperationQueue()

        /// Data caching queue. Default maximum concurrent task count is 2.
        public var dataCachingQueue = OperationQueue()

        /// Image decoding queue. Default maximum concurrent task count is 1.
        public var imageDecodingQueue = OperationQueue()

        /// Image encoding queue. Default maximum concurrent task count is 1.
        public var imageEncodingQueue = OperationQueue()

        /// Image processing queue. Default maximum concurrent task count is 2.
        public var imageProcessingQueue = OperationQueue()

        #if !os(macOS)
        /// Image decompressing queue. Default maximum concurrent task count is 2.
        public var imageDecompressingQueue = OperationQueue()
        #endif

        // MARK: - Processors

        /// Processors to be applied by default to all images loaded by the
        /// pipeline.
        /// If a request has a non-empty processors list, the pipeline won't
        /// apply its own processors, leaving the request as is.
        /// This lets clients have an override point on request basis.
        public var processors: [ImageProcessing] = []

        // MARK: - Options

        /// A queue on which all callbacks, like `progress` and `completion`
        /// callbacks are called. `.main` by default.
        public var callbackQueue = DispatchQueue.main

        #if !os(macOS)
        /// Decompresses the loaded images. `true` by default.
        ///
        /// Decompressing compressed image formats (such as JPEG) can significantly
        /// improve drawing performance as it allows a bitmap representation to be
        /// created in a background rather than on the main thread.
        public var isDecompressionEnabled = true
        #endif

        public var dataCacheOptions = DataCacheOptions()

        public struct DataCacheOptions {
            /// Specifies which content to store in the `dataCache`. By default, the
            /// pipeline only stores the original image data downloaded using `dataLoader`.
            /// It can be configured to encode and store processed images instead.
            ///
            /// - note: If you are creating multiple versions of the same image using
            /// different processors, it might be worth enabling both `.originalData`
            /// and `.encodedImages` cache to reuse the same downloaded data.
            ///
            /// - note: It might be worth enabling `.encodedImages` if you want to
            /// transcode downloaded images into a more efficient format, like HEIF.
            public var storedItems: Set<DataCacheItem> = [.originalImageData]
        }

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
        ///     ImageProcessors.Resize(size: CGSize(width: 44, height: 44)),
        ///     ImageProcessors.GaussianBlur(radius: 8)
        /// ]))
        /// pipeline.loadImage(with: ImageRequest(url: url, processors: [
        ///     ImageProcessors.Resize(size: CGSize(width: 44, height: 44))
        /// ]))
        /// ```
        ///
        /// Nuke will load the image data only once, resize the image once and
        /// apply the blur also only once. There is no duplicated work done at
        /// any stage.
        public var isDeduplicationEnabled = true

        /// `true` by default. If `true` the pipeline will rate limit requests
        /// to prevent trashing of the underlying systems (e.g. `URLSession`).
        /// The rate limiter only comes into play when the requests are started
        /// and cancelled at a high rate (e.g. scrolling through a collection view).
        public var isRateLimiterEnabled = true

        /// `false` by default. If `true` the pipeline will try to produce a new
        /// image each time it receives a new portion of data from data loader.
        /// The decoder used by the image loading session determines whether
        /// to produce a partial image or not. The default image decoder
        /// (`ImageDecoder`) supports progressive JPEG decoding.
        public var isProgressiveDecodingEnabled = false

        /// `false` by default. If `true`, the pipeline will store all of the
        /// progressively generated previews in the memory cache. All of the
        /// previews have `isPreview` flag set to `true`.
        public var isStoringPreviewsInMemoryCache = false

        /// If the data task is terminated (either because of a failure or a
        /// cancellation) and the image was partially loaded, the next load will
        /// resume where it left off. Supports both validators (`ETag`,
        /// `Last-Modified`). Resumable downloads are enabled by default.
        public var isResumableDataEnabled = true

        // MARK: - Options (Shared)

        /// If `true` pipeline will detect GIFs and set `animatedImageData`
        /// (`UIImage` property). It will also disable processing of such images,
        /// and alter the way cache cost is calculated. However, this will not
        /// enable actual animated image rendering. To do that take a look at
        /// satellite projects (FLAnimatedImage and Gifu plugins for Nuke).
        /// `false` by default (to preserve resources).
        static var _isAnimatedImageDataEnabled = false

        /// `false` by default. If `true`, enables `os_signpost` logging for
        /// measuring performance. You can visually see all the performance
        /// metrics in `os_signpost` Instrument. For more information see
        /// https://developer.apple.com/documentation/os/logging and
        /// https://developer.apple.com/videos/play/wwdc2018/405/.
        public static var isSignpostLoggingEnabled = false {
            didSet {
                log = isSignpostLoggingEnabled ?
                    OSLog(subsystem: "com.github.kean.Nuke.ImagePipeline", category: "Image Loading") :
                    .disabled
            }
        }

        static var isFastTrackDecodingEnabled = true

        // MARK: - Initializer

        public init(dataLoader: DataLoading = DataLoader()) {
            self.dataLoader = dataLoader

            self.dataLoadingQueue.maxConcurrentOperationCount = 6
            self.dataCachingQueue.maxConcurrentOperationCount = 2
            self.imageDecodingQueue.maxConcurrentOperationCount = 1
            self.imageEncodingQueue.maxConcurrentOperationCount = 1
            self.imageProcessingQueue.maxConcurrentOperationCount = 2
            #if !os(macOS)
            self.imageDecompressingQueue.maxConcurrentOperationCount = 2
            #endif
        }

        /// Creates a default configuration.
        /// - parameter dataLoader: `DataLoader()` by default.
        /// - parameter imageCache: `ImageCache.shared` by default.
        public init(dataLoader: DataLoading = DataLoader(), imageCache: ImageCaching?) {
            self.init(dataLoader: dataLoader)
            self.customImageCache = imageCache
            self.isCustomImageCacheProvided = true
        } // This init is going to be removed in the future
    }

    public enum DataCacheItem {
        /// Original image data.
        case originalImageData
        /// Final image with all processors applied.
        case finalImage
    }
}

// MARK: - ImagePipelineObserving

public enum ImageTaskEvent {
    case started
    case cancelled
    case priorityUpdated(priority: ImageRequest.Priority)
    case intermediateResponseReceived(response: ImageResponse)
    case progressUpdated(completedUnitCount: Int64, totalUnitCount: Int64)
    case completed(result: Result<ImageResponse, ImagePipeline.Error>)
}

/// Allows you to tap into internal events of the image pipeline. Events are
/// delivered on the internal serial dispatch queue.
public protocol ImagePipelineObserving {
    /// Delivers the events produced by the image tasks started via `loadImage` method.
    func pipeline(_ pipeline: ImagePipeline, imageTask: ImageTask, didReceiveEvent event: ImageTaskEvent)
}

extension ImageTaskEvent {
    init(_ event: Task<ImageResponse, ImagePipeline.Error>.Event) {
        switch event {
        case let .error(error):
            self = .completed(result: .failure(error))
        case let .value(response, isCompleted):
            if isCompleted {
                self = .completed(result: .success(response))
            } else {
                self = .intermediateResponseReceived(response: response)
            }
        case let .progress(progress):
            self = .progressUpdated(completedUnitCount: progress.completed, totalUnitCount: progress.total)
        }
    }
}
