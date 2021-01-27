// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

/// `ImagePipeline` loads and decodes image data, processes loaded images and
/// stores them in caches.
///
/// See [Nuke's README](https://github.com/kean/Nuke) for a detailed overview of
/// the image pipeline and all of the related classes.
///
/// If you want to build a system that fits your specific needs, see `ImagePipeline.Configuration`
/// for a list of the available options. You can set custom data loaders and caches, configure
/// image encoders and decoders, change the number of concurrent operations for each
/// individual stage, disable and enable features like deduplication and rate limiting, and more.
///
/// `ImagePipeline` is fully thread-safe.
public /* final */ class ImagePipeline {
    public let configuration: Configuration
    public var observer: ImagePipelineObserving?

    private var tasks = [ImageTask: TaskSubscription]()

    private let decompressedImageTasks: TaskPool<ImageRequest.LoadKeyForProcessedImage, ImageResponse, Error>
    private let processedImageTasks: TaskPool<ImageRequest.LoadKeyForProcessedImage, ImageResponse, Error>
    private let originalImageTasks: TaskPool<ImageRequest.LoadKeyForOriginalImage, ImageResponse, Error>
    private let originalImageDataTasks: TaskPool<ImageRequest.LoadKeyForOriginalImage, (Data, URLResponse?), Error>

    private var nextTaskId = Atomic<Int>(0)

    // The queue on which the entire subsystem is synchronized.
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.ImagePipeline", target: .global(qos: .userInitiated))
    private let log: OSLog
    private var isInvalidated = false

    let rateLimiter: RateLimiter?
    let id = UUID()

    /// Shared image pipeline.
    public static var shared = ImagePipeline()

    deinit {
        ResumableDataStorage.shared.unregister(self)
        #if TRACK_ALLOCATIONS
        Allocations.decrement("ImagePipeline")
        #endif
    }

    /// Initializes `ImagePipeline` instance with the given configuration.
    ///
    /// - parameter configuration: `Configuration()` by default.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.rateLimiter = configuration.isRateLimiterEnabled ? RateLimiter(queue: queue) : nil

        let isDeduplicationEnabled = configuration.isDeduplicationEnabled
        self.decompressedImageTasks = TaskPool(isDeduplicationEnabled)
        self.processedImageTasks = TaskPool(isDeduplicationEnabled)
        self.originalImageTasks = TaskPool(isDeduplicationEnabled)
        self.originalImageDataTasks = TaskPool(isDeduplicationEnabled)

        if Configuration.isSignpostLoggingEnabled {
            self.log = OSLog(subsystem: "com.github.kean.Nuke.ImagePipeline", category: "Image Loading")
        } else {
            self.log = .disabled
        }

        ResumableDataStorage.shared.register(self)

        #if TRACK_ALLOCATIONS
        Allocations.increment("ImagePipeline")
        #endif
    }

    public convenience init(_ configure: (inout ImagePipeline.Configuration) -> Void) {
        var configuration = ImagePipeline.Configuration()
        configure(&configuration)
        self.init(configuration: configuration)
    }

    /// Invalidates the pipeline and cancels all outstanding tasks.
    func invalidate() {
        queue.async {
            guard !self.isInvalidated else { return }
            self.isInvalidated = true
            self.tasks.keys.forEach(self.cancel)
        }
    }

    // MARK: - Loading Images

    @discardableResult
    public func loadImage(with request: ImageRequestConvertible,
                          queue: DispatchQueue? = nil,
                          completion: @escaping ImageTask.Completion) -> ImageTask {
        loadImage(with: request, queue: queue, progress: nil, completion: completion)
    }

    /// Loads an image for the given request using image loading pipeline.
    ///
    /// The pipeline first checks if the image or image data exists in any of its caches.
    /// It checks if the processed image exists in the memory cache, then if the processed
    /// image data exists in the custom data cache (disabled by default), then if the data
    /// cache contains the original image data. Only if there is no cached data, the pipeline
    /// will start loading the data. When the data is loaded the pipeline decodes it, applies
    /// the processors, and decompresses the image in the background.
    ///
    /// To learn more about the pipeine, see the [README](https://github.com/kean/Nuke).
    ///
    /// # Deduplication
    ///
    /// The pipeline avoids doing any duplicated work when loading images. For example,
    /// let's take these two requests:
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
    /// Nuke will load the data only once, resize the image once and blur it also only once.
    /// There is no duplicated work done. The work only gets canceled when all the registered
    /// requests are, and the priority is based on the highest priority of the registered requests.
    ///
    /// # Configuration
    ///
    /// See `ImagePipeline.Configuration` to learn more about the pipeline features and
    /// how to enable/disable them.
    ///
    /// - parameter queue: A queue on which to execute `progress` and `completion`
    /// callbacks. By default, the pipeline uses `.main` queue.
    /// - parameter progress: A closure to be called periodically on the main thread
    /// when the progress is updated. `nil` by default.
    /// - parameter completion: A closure to be called on the main thread when the
    /// request is finished. `nil` by default.
    @discardableResult
    public func loadImage(with request: ImageRequestConvertible,
                          queue callbackQueue: DispatchQueue? = nil,
                          progress progressHandler: ImageTask.ProgressHandler? = nil,
                          completion: ImageTask.Completion? = nil) -> ImageTask {
        loadImage(with: request.asImageRequest(), isMainThreadConfined: false, queue: callbackQueue, progress: progressHandler, completion: completion)
    }

    /// - parameter isMainThreadConfined: Enables some performance optimizations like
    /// lock-free `ImageTask`.
    func loadImage(with request: ImageRequest,
                   isMainThreadConfined: Bool,
                   queue callbackQueue: DispatchQueue?,
                   progress progressHandler: ImageTask.ProgressHandler?,
                   completion: ImageTask.Completion?) -> ImageTask {
        let request = inheritOptions(request)
        let task = ImageTask(taskId: nextTaskId.increment(), request: request, isMainThreadConfined: isMainThreadConfined, isDataTask: false)
        task.pipeline = self
        self.queue.async {
            self.startImageTask(task, callbackQueue: callbackQueue, progress: progressHandler, completion: completion)
        }
        return task
    }

    // MARK: - Loading Image Data

    @discardableResult
    public func loadData(with request: ImageRequestConvertible,
                         queue callbackQueue: DispatchQueue? = nil,
                         completion: @escaping (Result<(data: Data, response: URLResponse?), ImagePipeline.Error>) -> Void) -> ImageTask {
        loadData(with: request, queue: callbackQueue, progress: nil, completion: completion)
    }

    /// Loads the image data for the given request. The data doesn't get decoded or processed in any
    /// other way.
    ///
    /// You can call `loadImage(:)` for the request at any point after calling `loadData(:)`, the
    /// pipeline will use the same operation to load the data, no duplicated work will be performed.
    ///
    /// - parameter queue: A queue on which to execute `progress` and `completion`
    /// callbacks. By default, the pipeline uses `.main` queue.
    /// - parameter progress: A closure to be called periodically on the main thread
    /// when the progress is updated. `nil` by default.
    /// - parameter completion: A closure to be called on the main thread when the
    /// request is finished.
    @discardableResult
    public func loadData(with request: ImageRequestConvertible,
                         queue callbackQueue: DispatchQueue? = nil,
                         progress: ((_ completed: Int64, _ total: Int64) -> Void)? = nil,
                         completion: @escaping (Result<(data: Data, response: URLResponse?), ImagePipeline.Error>) -> Void) -> ImageTask {
        let request = request.asImageRequest()
        let task = ImageTask(taskId: nextTaskId.increment(), request: request, isDataTask: true)
        task.pipeline = self
        self.queue.async {
            self.startDataTask(task, callbackQueue: callbackQueue, progress: progress, completion: completion)
        }
        return task
    }

    // MARK: - Image Task Events

    func imageTaskCancelCalled(_ task: ImageTask) {
        queue.async {
            self.cancel(task)
        }
    }

    private func cancel(_ task: ImageTask) {
        guard let subscription = self.tasks.removeValue(forKey: task) else { return }
        if !task.isDataTask {
            self.send(.cancelled, task)
        }
        subscription.unsubscribe()
    }

    func imageTaskUpdatePriorityCalled(_ task: ImageTask, priority: ImageRequest.Priority) {
        queue.async {
            task._priority = priority
            guard let subscription = self.tasks[task] else { return }
            if !task.isDataTask {
                self.send(.priorityUpdated(priority: priority), task)
            }
            subscription.setPriority(priority.taskPriority)
        }
    }
}

// MARK: - Cache

public extension ImagePipeline {
    /// Returns a cached response from the memory cache.
    func cachedImage(for url: URL) -> ImageContainer? {
        cachedImage(for: ImageRequest(url: url))
    }

    /// Returns a cached response from the memory cache. Returns `nil` if the request disables
    /// memory cache reads.
    func cachedImage(for request: ImageRequest) -> ImageContainer? {
        guard request.options.memoryCacheOptions.isReadAllowed && request.cachePolicy != .reloadIgnoringCachedData else { return nil }

        let request = inheritOptions(request)
        return configuration.imageCache?[request]
    }

    internal func storeResponse(_ image: ImageContainer, for request: ImageRequest) {
        guard request.options.memoryCacheOptions.isWriteAllowed,
            !image.isPreview || configuration.isStoringPreviewsInMemoryCache else { return }
        configuration.imageCache?[request] = image
    }

    /// Returns a key used for disk cache (see `DataCaching`).
    func cacheKey(for request: ImageRequest, item: DataCacheItem) -> String {
        switch item {
        case .originalImageData: return request.makeCacheKeyForOriginalImageData()
        case .finalImage: return request.makeCacheKeyForFinalImageData()
        }
    }

    /// Removes cached image from all cache layers.
    func removeCachedImage(for request: ImageRequest) {
        let request = inheritOptions(request)

        configuration.imageCache?[request] = nil

        if let dataCache = configuration.dataCache {
            dataCache.removeData(for: request.makeCacheKeyForOriginalImageData())
            dataCache.removeData(for: request.makeCacheKeyForFinalImageData())
        }

        configuration.dataLoader.removeData(for: request.urlRequest)
    }
}

// MARK: - Starting Image Tasks (Private)

private extension ImagePipeline {
    func startImageTask(_ task: ImageTask,
                        callbackQueue: DispatchQueue?,
                        progress progressHandler: ImageTask.ProgressHandler?,
                        completion: ImageTask.Completion?) {
        guard !isInvalidated else { return }

        self.send(.started, task)

        tasks[task] = makeTaskLoadImage(for: task.request)
            .subscribe(priority: task._priority.taskPriority) { [weak self, weak task] event in
                guard let self = self, let task = task else { return }

                self.send(ImageTaskEvent(event), task)

                if event.isCompleted {
                    self.tasks[task] = nil
                }

                (callbackQueue ?? self.configuration.callbackQueue).async {
                    guard !task.isCancelled else { return }

                    switch event {
                    case let .value(response, isCompleted):
                        if isCompleted {
                            completion?(.success(response))
                        } else {
                            progressHandler?(response, task.completedUnitCount, task.totalUnitCount)
                        }
                    case let .progress(progress):
                        task.setProgress(progress)
                        progressHandler?(nil, progress.completed, progress.total)
                    case let .error(error):
                        completion?(.failure(error))
                    }
                }
        }
    }

    func startDataTask(_ task: ImageTask,
                       callbackQueue: DispatchQueue?,
                       progress progressHandler: ((_ completed: Int64, _ total: Int64) -> Void)?,
                       completion: @escaping (Result<(data: Data, response: URLResponse?), ImagePipeline.Error>) -> Void) {
        guard !isInvalidated else { return }

        tasks[task] = makeTaskLoadImageData(for: task.request)
            .subscribe(priority: task._priority.taskPriority) { [weak self, weak task] event in
                guard let self = self, let task = task else { return }

                if event.isCompleted {
                    self.tasks[task] = nil
                }

                (callbackQueue ?? self.configuration.callbackQueue).async {
                    guard !task.isCancelled else { return }

                    switch event {
                    case let .value(response, isCompleted):
                        if isCompleted {
                            completion(.success(response))
                        }
                    case let .progress(progress):
                        task.setProgress(progress)
                        progressHandler?(progress.completed, progress.total)
                    case let .error(error):
                        completion(.failure(error))
                    }
                }
        }
    }
}

// MARK: - Task Factory (Private)

// When you request an image, the pipeline creates the following dependency graph:
//
// TaskLoadImage -> TaskProcessImage* -> TaskDecodeImage -> TaskLoadImageData
//
// Each task represents a resource to be retrieved - processed image, original image, etc.
// Each task can be reuse of the same resource requested multiple times.

extension ImagePipeline {
    func makeTaskLoadImage(for request: ImageRequest) -> Task<ImageResponse, ImagePipeline.Error>.Publisher {
        decompressedImageTasks.publisherForKey(request.makeLoadKeyForFinalImage()) {
            TaskLoadImage(self, request, queue, log)
        }
    }

    func makeTaskProcessImage(for request: ImageRequest) -> Task<ImageResponse, ImagePipeline.Error>.Publisher {
        request.processors.isEmpty ?
            makeTaskDecodeImage(for: request) : // No processing needed
            processedImageTasks.publisherForKey(request.makeLoadKeyForFinalImage()) {
                TaskProcessImage(self, request, queue, log)
            }
    }

    func makeTaskDecodeImage(for request: ImageRequest) -> Task<ImageResponse, ImagePipeline.Error>.Publisher {
        originalImageTasks.publisherForKey(request.makeLoadKeyForOriginalImage()) {
            TaskDecodeImage(self, request, queue, log)
        }
    }

    func makeTaskLoadImageData(for request: ImageRequest) -> Task<(Data, URLResponse?), ImagePipeline.Error>.Publisher {
        originalImageDataTasks.publisherForKey(request.makeLoadKeyForOriginalImage()) {
            TaskLoadImageData(self, request, queue, log)
        }
    }
}

// MARK: - Misc (Private)

private extension ImagePipeline {
    /// Inherits some of the pipeline configuration options like processors.
    func inheritOptions(_ request: ImageRequest) -> ImageRequest {
        // Do not manipulate is the request has some processors already.
        guard request.processors.isEmpty, !configuration.processors.isEmpty else { return request }

        var request = request
        request.processors = configuration.processors
        return request
    }

    func send(_ event: ImageTaskEvent, _ task: ImageTask) {
        observer?.pipeline(self, imageTask: task, didReceiveEvent: event)
    }
}

// MARK: - Errors

public extension ImagePipeline {
    /// Represents all possible image pipeline errors.
    enum Error: Swift.Error, CustomDebugStringConvertible {
        /// Data loader failed to load image data with a wrapped error.
        case dataLoadingFailed(Swift.Error)
        /// Decoder failed to produce a final image.
        case decodingFailed
        /// Processor failed to produce a final image.
        case processingFailed

        public var debugDescription: String {
            switch self {
            case let .dataLoadingFailed(error): return "Failed to load image data: \(error)"
            case .decodingFailed: return "Failed to create an image from the image data"
            case .processingFailed: return "Failed to process the image"
            }
        }
    }
}

// MARK: - Testing

extension ImagePipeline {
    var taskCount: Int {
        tasks.count
    }
}
