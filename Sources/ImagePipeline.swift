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

    private let decompressedImageFetchTasks: TaskPool<ImageResponse, Error>
    private let processedImageFetchTasks: TaskPool<ImageResponse, Error>
    private let originalImageFetchTasks: TaskPool<ImageResponse, Error>
    private let originalImageDataFetchTasks: TaskPool<(Data, URLResponse?), Error>

    private var nextTaskId = Atomic<Int>(0)

    // The queue on which the entire subsystem is synchronized.
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.ImagePipeline", target: .global(qos: .userInitiated))
    let rateLimiter: RateLimiter?
    let log: OSLog

    // TODO: cleanup
    var syncQueue: DispatchQueue { queue }

    /// Shared image pipeline.
    public static var shared = ImagePipeline()

    /// Initializes `ImagePipeline` instance with the given configuration.
    ///
    /// - parameter configuration: `Configuration()` by default.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.rateLimiter = configuration.isRateLimiterEnabled ? RateLimiter(queue: queue) : nil

        let isDeduplicationEnabled = configuration.isDeduplicationEnabled
        self.decompressedImageFetchTasks = TaskPool(isDeduplicationEnabled)
        self.processedImageFetchTasks = TaskPool(isDeduplicationEnabled)
        self.originalImageFetchTasks = TaskPool(isDeduplicationEnabled)
        self.originalImageDataFetchTasks = TaskPool(isDeduplicationEnabled)

        if Configuration.isSignpostLoggingEnabled {
            self.log = OSLog(subsystem: "com.github.kean.Nuke.ImagePipeline", category: "Image Loading")
        } else {
            self.log = .disabled
        }
    }

    public convenience init(_ configure: (inout ImagePipeline.Configuration) -> Void) {
        var configuration = ImagePipeline.Configuration()
        configure(&configuration)
        self.init(configuration: configuration)
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
                          queue: DispatchQueue? = nil,
                          progress progressHandler: ImageTask.ProgressHandler? = nil,
                          completion: ImageTask.Completion? = nil) -> ImageTask {
        loadImage(with: request.asImageRequest(), isMainThreadConfined: false, queue: queue) { task, event in
            switch event {
            case let .value(response, isCompleted):
                if isCompleted {
                    completion?(.success(response))
                } else {
                    progressHandler?(response, task.completedUnitCount, task.totalUnitCount)
                }
            case let .progress(progress):
                progressHandler?(nil, progress.completed, progress.total)
            case let .error(error):
                completion?(.failure(error))
            }
        }
    }

    /// - parameter isMainThreadConfined: Enables some performance optimizations like
    /// lock-free `ImageTask`.
    func loadImage(with request: ImageRequest,
                   isMainThreadConfined: Bool,
                   queue: DispatchQueue?,
                   observer: @escaping (ImageTask, Task<ImageResponse, Error>.Event) -> Void) -> ImageTask {
        let request = inheritOptions(request)
        let task = ImageTask(taskId: nextTaskId.increment(), request: request, isMainThreadConfined: isMainThreadConfined, isDataTask: false, queue: queue)
        task.pipeline = self
        self.queue.async {
            self.startImageTask(task, observer: observer)
        }
        return task
    }

    // MARK: - Loading Image Data

    @discardableResult
    public func loadData(with request: ImageRequestConvertible,
                         queue: DispatchQueue? = nil,
                         completion: @escaping (Result<(data: Data, response: URLResponse?), ImagePipeline.Error>) -> Void) -> ImageTask {
        loadData(with: request, queue: queue, progress: nil, completion: completion)
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
                         queue: DispatchQueue? = nil,
                         progress: ((_ completed: Int64, _ total: Int64) -> Void)? = nil,
                         completion: @escaping (Result<(data: Data, response: URLResponse?), ImagePipeline.Error>) -> Void) -> ImageTask {
        let request = request.asImageRequest()
        let task = ImageTask(taskId: nextTaskId.increment(), request: request, isDataTask: true, queue: queue)
        task.pipeline = self
        self.queue.async {
            self.startDataTask(task, progress: progress, completion: completion)
        }
        return task
    }

    // MARK: - Image Task Events

    func imageTaskCancelCalled(_ task: ImageTask) {
        queue.async {
            guard let subscription = self.tasks.removeValue(forKey: task) else { return }
            if !task.isDataTask {
                self.send(.cancelled, task)
            }
            subscription.unsubscribe()
        }
    }

    func imageTaskUpdatePriorityCalled(_ task: ImageTask, priority: ImageRequest.Priority) {
        queue.async {
            task._priority = priority
            guard let subscription = self.tasks[task] else { return }
            if !task.isDataTask {
                self.send(.priorityUpdated(priority: priority), task)
            }
            subscription.setPriority(priority)
        }
    }
}

// MARK: - Image (In-Memory) Cache

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
}

// MARK: - Data Cache

public extension ImagePipeline {
    /// Returns a key used for disk cache (see `DataCaching`).
    func cacheKey(for request: ImageRequest, item: DataCacheItem) -> String {
        switch item {
        case .originalImageData: return request.makeCacheKeyForOriginalImageData()
        case .finalImage: return request.makeCacheKeyForFinalImageData()
        }
    }
}

// MARK: - Cache

public extension ImagePipeline {
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
    func startImageTask(_ task: ImageTask, observer: @escaping (ImageTask, Task<ImageResponse, Error>.Event) -> Void) {
        self.send(.started, task)

        tasks[task] = getDecompressedImage(for: task.request)
            .publisher
            .subscribe(priority: task._priority) { [weak self, weak task] event in
                guard let self = self, let task = task else { return }

                self.send(ImageTaskEvent(event), task)

                if event.isCompleted {
                    self.tasks[task] = nil
                }

                (task.queue ?? self.configuration.callbackQueue).async {
                    guard !task.isCancelled else { return }
                    if case let .progress(progress) = event {
                        task.setProgress(progress)
                    }
                    observer(task, event)
                }
        }
    }

    func startDataTask(_ task: ImageTask,
                       progress progressHandler: ((_ completed: Int64, _ total: Int64) -> Void)?,
                       completion: @escaping (Result<(data: Data, response: URLResponse?), ImagePipeline.Error>) -> Void) {
        tasks[task] = getOriginalImageData(for: task.request).publisher
            .subscribe(priority: task._priority) { [weak self, weak task] event in
                guard let self = self, let task = task else { return }

                if event.isCompleted {
                    self.tasks[task] = nil
                }

                (task.queue ?? self.configuration.callbackQueue).async {
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

// MARK: - Task Factory

// When you request an image, the pipeline creates the following dependency graph:
//
// DecompressedImageTask ->
// ProcessedImageTask ->
//   ProcessedImageTask* ->
// OriginalImageTask ->
// OriginalImageDataTask
//
// Each task represents a resource to be retrieved - processed image, original image, etc.
// Each task can be reuse of the same resource requested multiple times.

extension ImagePipeline {
    func getDecompressedImage(for request: ImageRequest) -> Task<ImageResponse, ImagePipeline.Error> {
        decompressedImageFetchTasks.reusableTaskForKey(request.makeLoadKeyForFinalImage()) {
            DecompressedImageTask(pipeline: self, request: request)
        }
    }

    func getProcessedImage(for request: ImageRequest) -> Task<ImageResponse, ImagePipeline.Error> {
        guard !request.processors.isEmpty else {
            return getOriginalImage(for: request) // No processing needed
        }
        return processedImageFetchTasks.reusableTaskForKey(request.makeLoadKeyForFinalImage()) {
            ProcessedImageTask(pipeline: self, request: request)
        }
    }

    func getOriginalImage(for request: ImageRequest) -> Task<ImageResponse, ImagePipeline.Error> {
        originalImageFetchTasks.reusableTaskForKey(request.makeLoadKeyForOriginalImage()) {
            OriginalImageTask(pipeline: self, request: request)
        }
    }

    func getOriginalImageData(for request: ImageRequest) -> Task<(Data, URLResponse?), ImagePipeline.Error> {
        originalImageDataFetchTasks.reusableTaskForKey(request.makeLoadKeyForOriginalImage()) {
            OriginalDataTask(pipeline: self, request: request)
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
internal extension ImagePipeline {
    var taskCount: Int {
        return tasks.count
    }
}
