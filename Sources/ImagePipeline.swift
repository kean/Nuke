// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

/// `ImagePipeline` will load and decode image data, process loaded images and
/// store them in caches.
///
/// See [Nuke's README](https://github.com/kean/Nuke) for a detailed overview of
/// the image pipeline and all of the related classes.
///
/// If you want to build a system that fits your specific needs, see `ImagePipeline.Configuration`
/// for a list of the available options. You can set custom data loaders and caches, configure
/// image encoders and decoders, change the number of concurrent operations for each
/// individual stage, disable and enable features like deduplication and rate limiting, and more.
///
/// `ImagePipeline` is thread-safe.
public /* final */ class ImagePipeline {
    public let configuration: Configuration

    // The queue in which the entire subsystem is synchronized.
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.ImagePipeline", target: .global(qos: .userInitiated))

    private var tasks = [ImageTask: TaskSubscription]()

    private let decompressedImageFetchTasks: TaskPool<ImageResponse, Error>
    private let processedImageFetchTasks: TaskPool<ImageResponse, Error>
    private var originalImageFetchTasks: TaskPool<ImageResponse, Error>
    private var originalImageDataFetchTasks: TaskPool<(Data, URLResponse?), Error>

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
        self.decompressedImageFetchTasks = TaskPool(isDeduplicationEnabled: isDeduplicationEnabled)
        self.processedImageFetchTasks = TaskPool(isDeduplicationEnabled: isDeduplicationEnabled)
        self.originalImageFetchTasks = TaskPool(isDeduplicationEnabled: isDeduplicationEnabled)
        self.originalImageDataFetchTasks = TaskPool(isDeduplicationEnabled: isDeduplicationEnabled)

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

    /// Loads an image with the given url.
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
    ///     ImageProcessor.Resize(size: CGSize(width: 44, height: 44)),
    ///     ImageProcessor.GaussianBlur(radius: 8)
    /// ]))
    /// pipeline.loadImage(with: ImageRequest(url: url, processors: [
    ///     ImageProcessor.Resize(size: CGSize(width: 44, height: 44))
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
    /// - parameter progress: A closure to be called periodically on the main thread
    /// when the progress is updated. `nil` by default.
    /// - parameter completion: A closure to be called on the main thread when the
    /// request is finished. `nil` by default.
    @discardableResult
    public func loadImage(with url: URL,
                          progress: ImageTask.ProgressHandler? = nil,
                          completion: ImageTask.Completion? = nil) -> ImageTask {
        return loadImage(with: ImageRequest(url: url), progress: progress, completion: completion)
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
    ///     ImageProcessor.Resize(size: CGSize(width: 44, height: 44)),
    ///     ImageProcessor.GaussianBlur(radius: 8)
    /// ]))
    /// pipeline.loadImage(with: ImageRequest(url: url, processors: [
    ///     ImageProcessor.Resize(size: CGSize(width: 44, height: 44))
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
    /// - parameter progress: A closure to be called periodically on the main thread
    /// when the progress is updated. `nil` by default.
    /// - parameter completion: A closure to be called on the main thread when the
    /// request is finished. `nil` by default.
    @discardableResult
    public func loadImage(with request: ImageRequest,
                          progress progressHandler: ImageTask.ProgressHandler? = nil,
                          completion: ImageTask.Completion? = nil) -> ImageTask {
        return loadImage(with: request, isMainThreadConfined: false) { task, event in
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
                   observer: @escaping (ImageTask, Task<ImageResponse, Error>.Event) -> Void) -> ImageTask {
        let task = ImageTask(taskId: nextTaskId.increment(), request: request, isMainThreadConfined: isMainThreadConfined)
        task.pipeline = self
        queue.async {
            self.startImageTask(task, observer: observer)
        }
        return task
    }

    // MARK: - Loading Image Data

    /// Loads the image data for the given request. The data doesn't get decoded or processed in any
    /// other way.
    ///
    /// You can call `loadImage(:)` for the request at any point after calling `loadData(:)`, the
    /// pipeline will use the same operation to load the data, no duplicated work will be performed.
    ///
    /// - parameter progress: A closure to be called periodically on the main thread
    /// when the progress is updated. `nil` by default.
    /// - parameter completion: A closure to be called on the main thread when the
    /// request is finished.
    @discardableResult
    public func loadData(with request: ImageRequest,
                         progress: ((_ completed: Int64, _ total: Int64) -> Void)? = nil,
                         completion: @escaping (Result<(data: Data, response: URLResponse?), ImagePipeline.Error>) -> Void) -> ImageTask {
        let task = ImageTask(taskId: nextTaskId.increment(), request: request)
        task.pipeline = self
        queue.async {
            self.startDataTask(task, progress: progress, completion: completion)
        }
        return task
    }

    // MARK: - Image Task Events

    func imageTaskCancelCalled(_ task: ImageTask) {
        queue.async {
            guard let subscription = self.tasks.removeValue(forKey: task) else { return }
            subscription.unsubscribe()
        }
    }

    func imageTaskUpdatePriorityCalled(_ task: ImageTask, priority: ImageRequest.Priority) {
        queue.async {
            task._priority = priority
            guard let subscription = self.tasks[task] else { return }
            subscription.setPriority(priority)
        }
    }

    // MARK: - Starting Image Tasks

    private func startImageTask(_ task: ImageTask, observer: @escaping (ImageTask, Task<ImageResponse, Error>.Event) -> Void) {
        self.tasks[task] = getDecompressedImage(for: task.request).subscribe(priority: task._priority) { [weak self, weak task] event in
            guard let self = self, let task = task else { return }

            if event.isCompleted {
                self.tasks[task] = nil
            }

            DispatchQueue.main.async {
                guard !task.isCancelled else { return }
                if case let .progress(progress) = event {
                    task.setProgress(progress)
                }
                observer(task, event)
            }
        }
    }

    private func startDataTask(_ task: ImageTask,
                               progress progressHandler: ((_ completed: Int64, _ total: Int64) -> Void)?,
                               completion: @escaping (Result<(data: Data, response: URLResponse?), ImagePipeline.Error>) -> Void) {
        self.tasks[task] = getOriginalImageData(for: task.request) .subscribe(priority: task._priority) { [weak self, weak task] event in
            guard let self = self, let task = task else { return }

            if event.isCompleted {
                self.tasks[task] = nil
            }

            DispatchQueue.main.async {
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

    // MARK: - Get Decompressed Image

    private typealias DecompressedImageFetchTask = Task<ImageResponse, Error>

    private func getDecompressedImage(for request: ImageRequest) -> DecompressedImageFetchTask {
        let key = request.makeLoadKeyForProcessedImage()
        return decompressedImageFetchTasks.task(withKey: key) { job in
            self.loadDecompressedImage(for: request, job: job)
        }
    }

    private func loadDecompressedImage(for request: ImageRequest, job: DecompressedImageFetchTask.Job) {
        if let response = cachedResponse(for: request) {
            return job.send(value: response, isCompleted: true)
        }

        job.dependency = getProcessedImage(for: request).map(job) { [weak self] image, isCompleted, job in
            self?.decompressProcessedImage(image, isCompleted: isCompleted, for: request, job: job)
        }
    }

    private func decompressProcessedImage(_ response: ImageResponse, isCompleted: Bool, for request: ImageRequest, job: DecompressedImageFetchTask.Job) {
        #if os(macOS)
        storeResponse(response, for: request, isCompleted: isCompleted)
        job.send(value: response, isCompleted: isCompleted) // There is no decompression on macOS
        #else
        guard configuration.isDecompressionEnabled &&
            ImageDecompression.isDecompressionNeeded(for: response.image) ?? false &&
            !(Configuration.isAnimatedImageDataEnabled && response.image.animatedImageData != nil) else {
                storeResponse(response, for: request, isCompleted: isCompleted)
                job.send(value: response, isCompleted: isCompleted)
                return
        }

        if isCompleted {
            job.operation?.cancel() // Cancel any potential pending progressive decompression tasks
        } else if job.operation != nil {
            return  // Back pressure - already decompressiong another progressive image
        }

        guard !job.isDisposed else { return }

        let operation = BlockOperation { [weak self, weak job] in
            guard let self = self, let job = job else { return }

            let signpost = Signpost(log: self.log)
            if #available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *) {
                os_signpost(.begin, log: self.log, name: "Decompress Image", signpostID: signpost.signpostID, "%{public}s image", "\(isCompleted ? "Final" : "Progressive")")
            }
            let response = response.map { ImageDecompression().decompress(image: $0) } ?? response
            signpost.log(.end, name: "Decompress Image")

            self.queue.async {
                self.storeResponse(response, for: request, isCompleted: isCompleted)
                job.send(value: response, isCompleted: isCompleted)
            }
        }
        job.operation = operation
        configuration.imageDecompressingQueue.addOperation(operation)
        #endif
    }

    /// Returns a cached response from the memory cache. Returns `nil` if the request disables
    /// memory cache reads.
    public func cachedResponse(for request: ImageRequest) -> ImageResponse? {
        guard request.options.memoryCacheOptions.isReadAllowed else { return nil }
        return configuration.imageCache?.cachedResponse(for: request)
    }

    private func storeResponse(_ response: ImageResponse, for request: ImageRequest, isCompleted: Bool) {
        guard isCompleted, request.options.memoryCacheOptions.isWriteAllowed else { return }
        configuration.imageCache?.storeResponse(response, for: request)
    }

    // MARK: - Get Processed Image

    private typealias ProcessedImageFetchTask = Task<ImageResponse, Error>

    private func getProcessedImage(for request: ImageRequest) -> ProcessedImageFetchTask {
        guard !request.processors.isEmpty else {
            return getOriginalImage(for: request) // No processing needed
        }

        let key = request.makeLoadKeyForProcessedImage()
        return processedImageFetchTasks.task(withKey: key) { job in
            self.loadProcessedImage(for: request, job: job)
        }
    }

    private func loadProcessedImage(for request: ImageRequest, job: ProcessedImageFetchTask.Job) {
        if let response = cachedResponse(for: request) {
            return job.send(value: response, isCompleted: true)
        }

        guard !request.processors.isEmpty, let dataCache = configuration.dataCache, configuration.isDataCachingForProcessedImagesEnabled else {
            return loadOriginaImage(for: request, job: job)
        }

        let key = request.makeCacheKeyForProcessedImageData()

        let operation = BlockOperation { [weak self, weak job] in
            guard let self = self, let job = job else { return }

            let signpost = Signpost(log: self.log)
            signpost.log(.begin, name: "Read Cached Processed Image Data")
            let data = dataCache.cachedData(for: key)
            signpost.log(.end, name: "Read Cached Processed Image Data")

            self.queue.async {
                if let data = data {
                    self.decodeProcessedImageData(data, for: request, job: job)
                } else {
                    self.loadOriginaImage(for: request, job: job)
                }
            }
        }
        job.operation = operation
        configuration.dataCachingQueue.addOperation(operation)
    }

    private func decodeProcessedImageData(_ data: Data, for request: ImageRequest, job: ProcessedImageFetchTask.Job) {
        guard !job.isDisposed else { return }

        let decoderContext = ImageDecodingContext(request: request, data: data, urlResponse: nil)
        let decoder = configuration.makeImageDecoder(decoderContext)

        let operation = BlockOperation { [weak self, weak job] in
            guard let self = self, let job = job else { return }

            let signpost = Signpost(log: self.log)
            signpost.log(.begin, name: "Decode Cached Processed Image Data")
            let response = decoder.decode(data, urlResponse: nil, isFinal: true)
            signpost.log(.end, name: "Decode Cached Processed Image Data")

            self.queue.async {
                if let response = response {
                    job.send(value: response, isCompleted: true)
                } else {
                    self.loadOriginaImage(for: request, job: job)
                }
            }
        }
        job.operation = operation
        configuration.imageDecodingQueue.addOperation(operation)
    }

    private func loadOriginaImage(for request: ImageRequest, job: ProcessedImageFetchTask.Job) {
        assert(!request.processors.isEmpty)
        guard !job.isDisposed, !request.processors.isEmpty else { return }

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
            processor = ImageProcessor.Composition(request.processors)
            subRequest.processors = []
        }
        job.dependency = getProcessedImage(for: subRequest).map(job) { [weak self] image, isCompleted, job in
            self?.processImage(image, isCompleted: isCompleted, for: request, processor: processor, job: job)
        }
    }

    private func processImage(_ response: ImageResponse, isCompleted: Bool, for request: ImageRequest, processor: ImageProcessing, job: ProcessedImageFetchTask.Job) {
        guard !(Configuration.isAnimatedImageDataEnabled && response.image.animatedImageData != nil) else {
            job.send(value: response, isCompleted: isCompleted)
            return
        }

        if isCompleted {
            job.operation?.cancel() // Cancel any potential pending progressive processing tasks
        } else if job.operation != nil {
            return  // Back pressure - already processing another progressive image
        }

        let operation = BlockOperation { [weak self, weak job] in
            guard let self = self, let job = job else { return }

            let signpost = Signpost(log: self.log)
            if #available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *) {
                os_signpost(.begin, log: self.log, name: "Process Image", signpostID: signpost.signpostID, "%{public}s, %{public}s image", "\(processor)", "\(isCompleted ? "final" : "progressive")")
            }
            let context = ImageProcessingContext(request: request, isFinal: isCompleted, scanNumber: response.scanNumber)
            let response = response.map { processor.process(image: $0, context: context) }
            signpost.log(.end, name: "Process Image")

            self.queue.async {
                guard let response = response else {
                    if isCompleted {
                        job.send(error: .processingFailed)
                    } // Ignore when progressive processing fails
                    return
                }
                if isCompleted {
                    self.storeProcessedImageInDataCache(response, request: request)
                }
                job.send(value: response, isCompleted: isCompleted)
            }
        }
        job.operation = operation
        configuration.imageProcessingQueue.addOperation(operation)
    }

    private func storeProcessedImageInDataCache(_ response: ImageResponse, request: ImageRequest) {
        guard let dataCache = configuration.dataCache, configuration.isDataCachingForProcessedImagesEnabled else {
            return
        }
        let context = ImageEncodingContext(request: request, image: response.image, urlResponse: response.urlResponse)
        let encoder = configuration.makeImageEncoder(context)
        configuration.imageEncodingQueue.addOperation {
            let signpost = Signpost(log: self.log)
            signpost.log(.begin, name: "Encode Image")
            let encodedData = encoder.encode(image: response.image)
            signpost.log(.end, name: "Encode Image")

            guard let data = encodedData else { return }
            let key = request.makeCacheKeyForProcessedImageData()
            dataCache.storeData(data, for: key) // This is instant
        }
    }

    // MARK: - Get Original Image

    private typealias OriginalImageFetchTask = Task<ImageResponse, Error>

    private final class OriginalImageFetchContext {
        let request: ImageRequest
        var decoder: ImageDecoding?

        init(request: ImageRequest) {
            self.request = request
        }
    }

    private func getOriginalImage(for request: ImageRequest) -> OriginalImageFetchTask {
        let key = request.makeLoadKeyForOriginalImage()
        return originalImageFetchTasks.task(withKey: key) { job in
            let context = OriginalImageFetchContext(request: request)
            let task = self.getOriginalImageData(for: request)
            job.dependency = task.map(job) { [weak self] value, isCompleted, job in
                self?.decodeData(value.0, urlResponse: value.1, isCompleted: isCompleted, job: job, context: context)
            }
        }
    }

    private func decodeData(_ data: Data, urlResponse: URLResponse?, isCompleted: Bool, job: OriginalImageFetchTask.Job, context: OriginalImageFetchContext) {
        if isCompleted {
            job.operation?.cancel() // Cancel any potential pending progressive decoding tasks
        } else if !configuration.isProgressiveDecodingEnabled || job.operation != nil {
            return // Back pressure - already decoding another progressive data chunk
        }

        // Sanity check
        guard !data.isEmpty else {
            if isCompleted {
                job.send(error: .decodingFailed)
            }
            return
        }

        let decoder = self.decoder(for: context, data: data, urlResponse: urlResponse)

        let operation = BlockOperation { [weak self, weak job] in
            guard let self = self, let job = job else { return }

            let signpost = Signpost(log: self.log)
            if #available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *) {
                os_signpost(.begin, log: self.log, name: "Decode Image Data", signpostID: signpost.signpostID, "%{public}s image", "\(isCompleted ? "Final" : "Progressive")")
            }
            let response = decoder.decode(data, urlResponse: urlResponse, isFinal: isCompleted)
            signpost.log(.end, name: "Decode Image Data")

            self.queue.async {
                if let response = response {
                    job.send(value: response, isCompleted: isCompleted)
                } else if isCompleted {
                    job.send(error: .decodingFailed)
                }
            }
        }
        job.operation = operation
        configuration.imageDecodingQueue.addOperation(operation)
    }

    // Lazily creates decoding for task
    private func decoder(for context: OriginalImageFetchContext, data: Data, urlResponse: URLResponse?) -> ImageDecoding {
        // Return the existing processor in case it has already been created.
        if let decoder = context.decoder {
            return decoder
        }
        let decoderContext = ImageDecodingContext(request: context.request, data: data, urlResponse: urlResponse)
        let decoder = configuration.makeImageDecoder(decoderContext)
        context.decoder = decoder
        return decoder
    }

    // MARK: - Get Original Image Data

    private typealias OriginalImageDataFetchTask = Task<(Data, URLResponse?), Error>

    private final class OriginalImageDataFetchContext {
        let request: ImageRequest
        var urlResponse: URLResponse?
        var resumableData: ResumableData?
        var resumedDataCount: Int64 = 0
        lazy var data = Data()

        init(request: ImageRequest) {
            self.request = request
        }
    }

    private func getOriginalImageData(for request: ImageRequest) -> OriginalImageDataFetchTask {
        let key = request.makeLoadKeyForOriginalImage()
        return originalImageDataFetchTasks.task(withKey: key) { job in
            let context = OriginalImageDataFetchContext(request: request)
            if self.configuration.isRateLimiterEnabled {
                // Rate limiter is synchronized on pipeline's queue. Delayed work is
                // executed asynchronously also on this same queue.
                self.rateLimiter.execute { [weak self, weak job] in
                    guard let self = self, let job = job, !job.isDisposed else {
                        return false
                    }
                    self.loadImageDataFromCache(for: job, context: context)
                    return true
                }
            } else { // Start loading immediately.
                self.loadImageDataFromCache(for: job, context: context)
            }
        }
    }

    private func loadImageDataFromCache(for job: OriginalImageDataFetchTask.Job, context: OriginalImageDataFetchContext) {
        guard let cache = configuration.dataCache, configuration.isDataCachingForOriginalImageDataEnabled else {
            loadImageData(for: job, context: context) // Skip disk cache lookup, load data
            return
        }

        let key = context.request.makeCacheKeyForOriginalImageData()
        let operation = BlockOperation { [weak self, weak job] in
            guard let self = self, let job = job else { return }

            let signpost = Signpost(log: self.log)
            signpost.log(.begin, name: "Read Cached Image Data")
            let data = cache.cachedData(for: key)
            signpost.log(.end, name: "Read Cached Image Data")

            self.queue.async {
                if let data = data {
                    job.send(value: (data, nil), isCompleted: true)
                } else {
                    self.loadImageData(for: job, context: context)
                }
            }
        }
        job.operation = operation
        configuration.dataCachingQueue.addOperation(operation)
    }

    private func loadImageData(for job: OriginalImageDataFetchTask.Job, context: OriginalImageDataFetchContext) {
        // Wrap data request in an operation to limit maximum number of
        // concurrent data tasks.
        let operation = Operation(starter: { [weak self, weak job] finish in
            guard let self = self, let job = job else {
                return finish()
            }
            self.queue.async {
                self.loadImageData(for: job, context: context, finish: finish)
            }
        })
        configuration.dataLoadingQueue.addOperation(operation)
        job.operation = operation
    }

    // This methods gets called inside data loading operation (Operation).
    private func loadImageData(for job: OriginalImageDataFetchTask.Job, context: OriginalImageDataFetchContext, finish: @escaping () -> Void) {
        guard !job.isDisposed else {
            return finish() // Task was cancelled by the time it got the chance to start
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

        let signpost = Signpost(log: self.log)
        if #available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *) {
            os_signpost(.begin, log: self.log, name: "Load Image Data", signpostID: signpost.signpostID, "URL: %s, resumable data: %{xcode:size-in-bytes}d", urlRequest.url?.absoluteString ?? "", context.resumableData?.data.count ?? 0)
        }

        let dataTask = configuration.dataLoader.loadData(
            with: urlRequest,
            didReceiveData: { [weak self, weak job] data, response in
                guard let self = self, let job = job else { return }
                self.queue.async {
                    self.imageDataLoadingJob(job, context: context, didReceiveData: data, response: response, signpost: signpost)
                }
            },
            completion: { [weak self, weak job] error in
                finish() // Finish the operation!
                guard let self = self, let job = job else { return }
                self.queue.async {
                    if #available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *) {
                        os_signpost(.end, log: self.log, name: "Load Image Data", signpostID: signpost.signpostID, "Finished with size %{xcode:size-in-bytes}d", context.data.count)
                    }
                    self.imageDataLoadingJob(job, context: context, didFinishLoadingDataWithError: error)
                }
        })

        job.onCancelled = { [weak self] in
            guard let self = self else { return }

            if #available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *) {
                os_signpost(.end, log: self.log, name: "Load Image Data", signpostID: signpost.signpostID, "Cancelled")
            }

            dataTask.cancel()
            finish() // Finish the operation!

            self.tryToSaveResumableData(for: context)
        }
    }

    private func imageDataLoadingJob(_ job: OriginalImageDataFetchTask.Job, context: OriginalImageDataFetchContext, didReceiveData chunk: Data, response: URLResponse, signpost: Signpost) {
        // Check if this is the first response.
        if context.urlResponse == nil {
            // See if the server confirmed that the resumable data can be used
            if let resumableData = context.resumableData {
                if ResumableData.isResumedResponse(response) {
                    context.data = resumableData.data
                    context.resumedDataCount = Int64(resumableData.data.count)
                    if #available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *) {
                        os_signpost(.event, log: self.log, name: "Load Image Data", signpostID: signpost.signpostID, "Resumed with data %{xcode:size-in-bytes}d", context.resumedDataCount)
                    }
                }
                context.resumableData = nil // Get rid of resumable data
            }
        }

        // Append data and save response
        context.data.append(chunk)
        context.urlResponse = response

        let progress = TaskProgress(completed: Int64(context.data.count), total: response.expectedContentLength + context.resumedDataCount)
        job.send(progress: progress)

        // If the image hasn't been fully loaded yet, give decoder a change
        // to decode the data chunk. In case `expectedContentLength` is `0`,
        // progressive decoding doesn't run.
        guard context.data.count < response.expectedContentLength else { return }

        job.send(value: (context.data, response))
    }

    private func imageDataLoadingJob(_ job: OriginalImageDataFetchTask.Job, context: OriginalImageDataFetchContext, didFinishLoadingDataWithError error: Swift.Error?) {
        if let error = error {
            tryToSaveResumableData(for: context)
            job.send(error: .dataLoadingFailed(error))
            return
        }

        // Sanity check, should never happen in practice
        guard !context.data.isEmpty else {
            job.send(error: .dataLoadingFailed(URLError(.unknown, userInfo: [:])))
            return
        }

        // Store in data cache
        if let dataCache = configuration.dataCache, configuration.isDataCachingForOriginalImageDataEnabled {
            let key = context.request.makeCacheKeyForOriginalImageData()
            dataCache.storeData(context.data, for: key)
        }

        job.send(value: (context.data, context.urlResponse), isCompleted: true)
    }

    private func tryToSaveResumableData(for context: OriginalImageDataFetchContext) {
        // Try to save resumable data in case the task was cancelled
        // (`URLError.cancelled`) or failed to complete with other error.
        if configuration.isResumableDataEnabled,
            let response = context.urlResponse, !context.data.isEmpty,
            let resumableData = ResumableData(response: response, data: context.data) {
            ResumableData.storeResumableData(resumableData, for: context.request.urlRequest)
        }
    }

    // MARK: - Errors

    /// Represents all possible image pipeline errors.
    public enum Error: Swift.Error, CustomDebugStringConvertible {
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
