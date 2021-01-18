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

    // The queue on which the entire subsystem is synchronized.
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.ImagePipeline", target: .global(qos: .userInitiated))

    private var tasks = [ImageTask: TaskSubscription]()

    private let decompressedImageFetchTasks: TaskPool<ImageResponse, Error>
    private let processedImageFetchTasks: TaskPool<ImageResponse, Error>
    private let originalImageFetchTasks: TaskPool<ImageResponse, Error>
    private let originalImageDataFetchTasks: TaskPool<(Data, URLResponse?), Error>

    private var nextTaskId = Atomic<Int>(0)

    private let rateLimiter: RateLimiter

    private let log: OSLog

    /// Shared image pipeline.
    public static var shared = ImagePipeline()

    /// Initializes `ImagePipeline` instance with the given configuration.
    ///
    /// - parameter configuration: `Configuration()` by default.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.rateLimiter = RateLimiter(queue: queue)

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

    private func storeResponse(_ image: ImageContainer, for request: ImageRequest) {
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
        tasks[task] = getOriginalImageData(for: task.request)
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

// MARK: - Get Decompressed Image (Private)

private extension ImagePipeline {
    typealias DecompressedImageTask = Task<ImageResponse, Error>

    func getDecompressedImage(for request: ImageRequest) -> DecompressedImageTask.Publisher {
        let key = request.makeLoadKeyForFinalImage()
        return decompressedImageFetchTasks.task(withKey: key, starter: { task in
            self.performDecompressedImageFetchTask(task, request: request)
        }).publisher
    }

    func performDecompressedImageFetchTask(_ task: DecompressedImageTask, request: ImageRequest) {
        if let image = cachedImage(for: request) {
            let response = ImageResponse(container: image)
            if image.isPreview {
                task.send(value: response)
            } else {
                return task.send(value: response, isCompleted: true)
            }
        }

        guard let dataCache = configuration.dataCache, configuration.dataCacheOptions.storedItems.contains(.finalImage), request.cachePolicy != .reloadIgnoringCachedData else {
            return loadDecompressedImage(for: request, task: task)
        }

        // Load processed image from data cache and decompress it.
        let key = cacheKey(for: request, item: .finalImage)
        let operation = BlockOperation { [weak self, weak task] in
            guard let self = self, let task = task else { return }

            let log = Log(self.log, "Read Cached Processed Image Data")
            log.signpost(.begin)
            let data = dataCache.cachedData(for: key)
            log.signpost(.end)

            self.queue.async {
                if let data = data {
                    self.decodeProcessedImageData(data, for: request, task: task)
                } else {
                    self.loadDecompressedImage(for: request, task: task)
                }
            }
        }
        task.operation = operation
        configuration.dataCachingQueue.addOperation(operation)
    }

    func decodeProcessedImageData(_ data: Data, for request: ImageRequest, task: ProcessedImageTask) {
        guard !task.isDisposed else { return }

        let decoderContext = ImageDecodingContext(request: request, data: data, isCompleted: true, urlResponse: nil)
        guard let decoder = configuration.makeImageDecoder(decoderContext) else {
            // This shouldn't happen in practice unless encoder/decoder pair
            // for data cache is misconfigured.
            return self.loadDecompressedImage(for: request, task: task)
        }

        let operation = BlockOperation { [weak self, weak task] in
            guard let self = self, let task = task else { return }

            let log = Log(self.log, "Decode Cached Processed Image Data")
            log.signpost(.begin)
            let response = decoder.decode(data, urlResponse: nil, isCompleted: true)
            log.signpost(.end)

            self.queue.async {
                if let response = response {
                    self.decompressProcessedImage(response, isCompleted: true, for: request, task: task)
                } else {
                    self.loadDecompressedImage(for: request, task: task)
                }
            }
        }
        task.operation = operation
        configuration.imageDecodingQueue.addOperation(operation)
    }

    func loadDecompressedImage(for request: ImageRequest, task: DecompressedImageTask) {
        task.dependency = getProcessedImage(for: request).subscribe(task) { [weak self] image, isCompleted, task in
            self?.storeDecompressedImageInDataCache(image, request: request)
            self?.decompressProcessedImage(image, isCompleted: isCompleted, for: request, task: task)
        }
    }

    #if os(macOS)
    func decompressProcessedImage(_ response: ImageResponse, isCompleted: Bool, for request: ImageRequest, task: DecompressedImageTask) {
        storeResponse(response.container, for: request)
        task.send(value: response, isCompleted: isCompleted) // There is no decompression on macOS
    }
    #else
    func decompressProcessedImage(_ response: ImageResponse, isCompleted: Bool, for request: ImageRequest, task: DecompressedImageTask) {
        guard isDecompressionNeeded(for: response) else {
            storeResponse(response.container, for: request)
            task.send(value: response, isCompleted: isCompleted)
            return
        }

        if isCompleted {
            task.operation?.cancel() // Cancel any potential pending progressive decompression tasks
        } else if task.operation != nil {
            return  // Back-pressure: we are receiving data too fast
        }

        guard !task.isDisposed else { return }

        let operation = BlockOperation { [weak self, weak task] in
            guard let self = self, let task = task else { return }

            let log = Log(self.log, "Decompress Image")
            log.signpost(.begin, isCompleted ? "Final image" : "Progressive image")
            let response = response.map { $0.map(ImageDecompression.decompress(image:)) } ?? response
            log.signpost(.end)

            self.queue.async {
                self.storeResponse(response.container, for: request)
                task.send(value: response, isCompleted: isCompleted)
            }
        }
        task.operation = operation
        configuration.imageDecompressingQueue.addOperation(operation)
    }

    func isDecompressionNeeded(for response: ImageResponse) -> Bool {
        return configuration.isDecompressionEnabled &&
            ImageDecompression.isDecompressionNeeded(for: response.image) ?? false &&
            !(Configuration._isAnimatedImageDataEnabled && response.image._animatedImageData != nil)
    }
    #endif

    func storeDecompressedImageInDataCache(_ response: ImageResponse, request: ImageRequest) {
        guard let dataCache = configuration.dataCache, configuration.dataCacheOptions.storedItems.contains(.finalImage) else {
            return
        }
        let context = ImageEncodingContext(request: request, image: response.image, urlResponse: response.urlResponse)
        let encoder = configuration.makeImageEncoder(context)
        configuration.imageEncodingQueue.addOperation { [weak self] in
            guard let self = self else { return }

            let log = Log(self.log, "Encode Image")
            log.signpost(.begin)
            let encodedData = encoder.encode(response.container, context: context)
            log.signpost(.end)

            guard let data = encodedData else { return }
            let key = self.cacheKey(for: request, item: .finalImage)
            dataCache.storeData(data, for: key) // This is instant
        }
    }
}

// MARK: - Get Processed Image (Private)

private extension ImagePipeline {
    typealias ProcessedImageTask = Task<ImageResponse, Error>

    func getProcessedImage(for request: ImageRequest) -> ProcessedImageTask.Publisher {
        guard !request.processors.isEmpty else {
            return getOriginalImage(for: request) // No processing needed
        }

        let key = request.makeLoadKeyForFinalImage()
        return processedImageFetchTasks.task(withKey: key, starter: { task in
            self.performProcessedImageFetchTask(task, request: request)
        }).publisher
    }

    func performProcessedImageFetchTask(_ task: ProcessedImageTask, request: ImageRequest) {
        assert(!request.processors.isEmpty)
        guard !task.isDisposed, !request.processors.isEmpty else { return }

        if let image = cachedImage(for: request), !image.isPreview {
            return task.send(value: ImageResponse(container: image), isCompleted: true)
        }

        let processor: ImageProcessing
        var subRequest = request
        if configuration.isDeduplicationEnabled {
            // Recursively call getProcessedImage until there are no more processors left.
            // Each time getProcessedImage is called it tries to find an existing
            // task ("deduplication") to avoid doing any duplicated work.
            processor = request.processors.last!
            subRequest.processors = Array(request.processors.dropLast())
        } else {
            // Perform all transformations in one go
            processor = ImageProcessors.Composition(request.processors)
            subRequest.processors = []
        }
        task.dependency = getProcessedImage(for: subRequest).subscribe(task) { [weak self] image, isCompleted, task in
            self?.processImage(image, isCompleted: isCompleted, for: request, processor: processor, task: task)
        }
    }

    func processImage(_ response: ImageResponse, isCompleted: Bool, for request: ImageRequest, processor: ImageProcessing, task: ProcessedImageTask) {
        guard !(Configuration._isAnimatedImageDataEnabled && response.image._animatedImageData != nil) else {
            task.send(value: response, isCompleted: isCompleted)
            return
        }

        if isCompleted {
            task.operation?.cancel() // Cancel any potential pending progressive processing tasks
        } else if task.operation != nil {
            return  // Back pressure - already processing another progressive image
        }

        let operation = BlockOperation { [weak self, weak task] in
            guard let self = self, let task = task else { return }

            let log = Log(self.log, "Process Image")
            log.signpost(.begin, "\(processor), \(isCompleted ? "final" : "progressive") image")
            let context = ImageProcessingContext(request: request, response: response, isFinal: isCompleted)
            let response = response.map { processor.process($0, context: context) }
            log.signpost(.end)

            self.queue.async {
                guard let response = response else {
                    if isCompleted {
                        task.send(error: .processingFailed)
                    } // Ignore when progressive processing fails
                    return
                }
                task.send(value: response, isCompleted: isCompleted)
            }
        }
        task.operation = operation
        configuration.imageProcessingQueue.addOperation(operation)
    }
}

// MARK: - Get Original Image (Private)

private extension ImagePipeline {
    typealias OriginalImageTask = Task<ImageResponse, Error>

    final class OriginalImageTaskContext {
        let request: ImageRequest
        var decoder: ImageDecoding?

        init(request: ImageRequest) {
            self.request = request
        }
    }

    func getOriginalImage(for request: ImageRequest) -> OriginalImageTask.Publisher {
        let key = request.makeLoadKeyForOriginalImage()
        return originalImageFetchTasks.task(withKey: key, starter: { task in
            let context = OriginalImageTaskContext(request: request)
            task.dependency = self.getOriginalImageData(for: request)
                .subscribe(task) { [weak self] value, isCompleted, task in
                    self?.decodeData(value.0, urlResponse: value.1, isCompleted: isCompleted, task: task, context: context)
            }
        }).publisher
    }

    func decodeData(_ data: Data, urlResponse: URLResponse?, isCompleted: Bool, task: OriginalImageTask, context: OriginalImageTaskContext) {
        if isCompleted {
            task.operation?.cancel() // Cancel any potential pending progressive decoding tasks
        } else if !configuration.isProgressiveDecodingEnabled || task.operation != nil {
            return // Back pressure - already decoding another progressive data chunk
        }

        // Sanity check
        guard !data.isEmpty else {
            if isCompleted {
                task.send(error: .decodingFailed)
            }
            return
        }

        guard let decoder = self.decoder(for: context, data: data, urlResponse: urlResponse, isCompleted: isCompleted) else {
            if isCompleted {
                task.send(error: .decodingFailed)
            } // Try again when more data is downloaded.
            return
        }

        let operation = BlockOperation { [weak self, weak task] in
            guard let self = self, let task = task else { return }

            let log = Log(self.log, "Decode Image Data")
            log.signpost(.begin, "\(isCompleted ? "Final" : "Progressive") image")
            let response = decoder.decode(data, urlResponse: urlResponse, isCompleted: isCompleted)
            log.signpost(.end)

            self.queue.async {
                if let response = response {
                    task.send(value: response, isCompleted: isCompleted)
                } else if isCompleted {
                    task.send(error: .decodingFailed)
                }
            }
        }
        task.operation = operation
        configuration.imageDecodingQueue.addOperation(operation)
    }

    // Lazily creates decoding for task
    func decoder(for context: OriginalImageTaskContext, data: Data, urlResponse: URLResponse?, isCompleted: Bool) -> ImageDecoding? {
        // Return the existing processor in case it has already been created.
        if let decoder = context.decoder {
            return decoder
        }
        let decoderContext = ImageDecodingContext(request: context.request, data: data, isCompleted: isCompleted, urlResponse: urlResponse)
        let decoder = configuration.makeImageDecoder(decoderContext)
        context.decoder = decoder
        return decoder
    }
}

// MARK: - Get Original Image Data (Private)

private extension ImagePipeline {
    typealias OriginalImageDataTask = Task<(Data, URLResponse?), Error>

    final class OriginalImageDataTaskContext {
        let request: ImageRequest
        var urlResponse: URLResponse?
        var resumableData: ResumableData?
        var resumedDataCount: Int64 = 0
        lazy var data = Data()

        init(request: ImageRequest) {
            self.request = request
        }
    }

    func getOriginalImageData(for request: ImageRequest) -> OriginalImageDataTask.Publisher {
        let key = request.makeLoadKeyForOriginalImage()
        return originalImageDataFetchTasks.task(withKey: key, starter: { task in
            let context = OriginalImageDataTaskContext(request: request)
            if self.configuration.isRateLimiterEnabled {
                // Rate limiter is synchronized on pipeline's queue. Delayed work is
                // executed asynchronously also on this same queue.
                self.rateLimiter.execute { [weak self, weak task] in
                    guard let self = self, let task = task, !task.isDisposed else {
                        return false
                    }
                    self.performOriginalImageDataTask(task, context: context)
                    return true
                }
            } else { // Start loading immediately.
                self.performOriginalImageDataTask(task, context: context)
            }
        }).publisher
    }

    func performOriginalImageDataTask(_ task: OriginalImageDataTask, context: OriginalImageDataTaskContext) {
        guard let cache = configuration.dataCache, configuration.dataCacheOptions.storedItems.contains(.originalImageData), context.request.cachePolicy != .reloadIgnoringCachedData else {
            loadImageData(for: task, context: context) // Skip disk cache lookup, load data
            return
        }

        let key = cacheKey(for: context.request, item: .originalImageData)
        let operation = BlockOperation { [weak self, weak task] in
            guard let self = self, let task = task else { return }

            let log = Log(self.log, "Read Cached Image Data")
            log.signpost(.begin)
            let data = cache.cachedData(for: key)
            log.signpost(.end)

            self.queue.async {
                if let data = data {
                    task.send(value: (data, nil), isCompleted: true)
                } else {
                    self.loadImageData(for: task, context: context)
                }
            }
        }
        task.operation = operation
        configuration.dataCachingQueue.addOperation(operation)
    }

    func loadImageData(for task: OriginalImageDataTask, context: OriginalImageDataTaskContext) {
        // Wrap data request in an operation to limit maximum number of
        // concurrent data tasks.
        let operation = Operation(starter: { [weak self, weak task] finish in
            guard let self = self, let task = task else {
                return finish()
            }
            self.queue.async {
                self.loadImageData(for: task, context: context, finish: finish)
            }
        })
        configuration.dataLoadingQueue.addOperation(operation)
        task.operation = operation
    }

    // This methods gets called inside data loading operation (Operation).
    func loadImageData(for task: OriginalImageDataTask, context: OriginalImageDataTaskContext, finish: @escaping () -> Void) {
        guard !task.isDisposed else {
            return finish() // Task was cancelled by the time it got a chance to start
        }

        var urlRequest = context.request.urlRequest

        // Read and remove resumable data from cache (we're going to insert it
        // back in the cache if the request fails to complete again).
        if configuration.isResumableDataEnabled,
            let resumableData = ResumableData.removeResumableData(for: urlRequest) {
            // Update headers to add "Range" and "If-Range" headers
            resumableData.resume(request: &urlRequest)
            // Save resumable data to be used later (before using it, the pipeline
            // verifies that the server returns "206 Partial Content")
            context.resumableData = resumableData
        }

        let log = Log(self.log, "Load Image Data")
        log.signpost(.begin, "URL: \(urlRequest.url?.absoluteString ?? ""), resumable data: \(Log.bytes(context.resumableData?.data.count ?? 0))")

        let dataTask = configuration.dataLoader.loadData(
            with: urlRequest,
            didReceiveData: { [weak self, weak task] data, response in
                guard let self = self, let task = task else { return }
                self.queue.async {
                    self.imageDataLoadingTask(task, context: context, didReceiveData: data, response: response, log: log)
                }
            },
            completion: { [weak self, weak task] error in
                finish() // Finish the operation!
                guard let self = self, let task = task else { return }
                self.queue.async {
                    log.signpost(.end, "Finished with size \(Log.bytes(context.data.count))")
                    self.imageDataLoadingTask(task, context: context, didFinishLoadingDataWithError: error)
                }
        })

        task.onCancelled = { [weak self] in
            guard let self = self else { return }

            log.signpost(.end, "Cancelled")
            dataTask.cancel()
            finish() // Finish the operation!

            self.tryToSaveResumableData(for: context)
        }
    }

    func imageDataLoadingTask(_ task: OriginalImageDataTask, context: OriginalImageDataTaskContext, didReceiveData chunk: Data, response: URLResponse, log: Log) {
        // Check if this is the first response.
        if context.urlResponse == nil {
            // See if the server confirmed that the resumable data can be used
            if let resumableData = context.resumableData, ResumableData.isResumedResponse(response) {
                context.data = resumableData.data
                context.resumedDataCount = Int64(resumableData.data.count)
                log.signpost(.event, "Resumed with data \(Log.bytes(context.resumedDataCount))")
            }
            context.resumableData = nil // Get rid of resumable data
        }

        // Append data and save response
        context.data.append(chunk)
        context.urlResponse = response

        let progress = TaskProgress(completed: Int64(context.data.count), total: response.expectedContentLength + context.resumedDataCount)
        task.send(progress: progress)

        // If the image hasn't been fully loaded yet, give decoder a change
        // to decode the data chunk. In case `expectedContentLength` is `0`,
        // progressive decoding doesn't run.
        guard context.data.count < response.expectedContentLength else { return }

        task.send(value: (context.data, response))
    }

    func imageDataLoadingTask(_ task: OriginalImageDataTask, context: OriginalImageDataTaskContext, didFinishLoadingDataWithError error: Swift.Error?) {
        if let error = error {
            tryToSaveResumableData(for: context)
            task.send(error: .dataLoadingFailed(error))
            return
        }

        // Sanity check, should never happen in practice
        guard !context.data.isEmpty else {
            task.send(error: .dataLoadingFailed(URLError(.unknown, userInfo: [:])))
            return
        }

        // Store in data cache
        if let dataCache = configuration.dataCache, configuration.dataCacheOptions.storedItems.contains(.originalImageData) {
            let key = cacheKey(for: context.request, item: .originalImageData)
            dataCache.storeData(context.data, for: key)
        }

        task.send(value: (context.data, context.urlResponse), isCompleted: true)
    }

    func tryToSaveResumableData(for context: OriginalImageDataTaskContext) {
        // Try to save resumable data in case the task was cancelled
        // (`URLError.cancelled`) or failed to complete with other error.
        if configuration.isResumableDataEnabled,
            let response = context.urlResponse, !context.data.isEmpty,
            let resumableData = ResumableData(response: response, data: context.data) {
            ResumableData.storeResumableData(resumableData, for: context.request.urlRequest)
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
