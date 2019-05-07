// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

/// `ImagePipeline` will load and decode image data, process loaded images and
/// store them in caches.
///
/// See [Nuke's README](https://github.com/kean/Nuke) for a detailed overview of
/// the image pipeline and all of the related classes.
///
/// `ImagePipeline` is created with a configuration (`Configuration`).
///
/// `ImagePipeline` is thread-safe.
public /* final */ class ImagePipeline: ImageTaskManaging {
    public let configuration: Configuration

    // This is a queue on which we access the sessions.
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.ImagePipeline")

    private var tasks = [ImageTask: ImageTaskExecutionContext]()

    private var processingTasks: [AnyHashable: ImageProcessingTask]?
    private var decodingTasks: [AnyHashable: ImageDecodingTask]?
    private var dataLoadingTasks: [AnyHashable: ImageDataLoadingTask]?

    private var nextTaskId = Atomic<Int>(0)

    private let rateLimiter: RateLimiter

    /// Shared image pipeline.
    public static var shared = ImagePipeline()

    /// The closure that gets called each time the task is completed (or cancelled).
    /// Guaranteed to be called on the main thread.
    public var didFinishCollectingMetrics: ((ImageTask, ImageTaskMetrics) -> Void)?

    // MARK: - Configuration

    public struct Configuration {
        /// Image cache used by the pipeline.
        public var imageCache: ImageCaching?

        /// Data loader used by the pipeline.
        public var dataLoader: DataLoading

        /// Data loading queue. Default maximum concurrent task count is 6.
        public var dataLoadingQueue = OperationQueue()

        /// Data cache used by the pipeline.
        public var dataCache: DataCaching?

        /// Data caching queue. Default maximum concurrent task count is 2.
        public var dataCachingQueue = OperationQueue()

        /// Default implementation uses shared `ImageDecoderRegistry` to create
        /// a decoder that matches the context.
        var imageDecoder: (ImageDecodingContext) -> ImageDecoding = {
            return ImageDecoderRegistry.shared.decoder(for: $0)
        }

        /// Image decoding queue. Default maximum concurrent task count is 1.
        public var imageDecodingQueue = OperationQueue()

        /// Image processing queue. Default maximum concurrent task count is 2.
        public var imageProcessingQueue = OperationQueue()

        #if !os(macOS)
        /// Decompresses the loaded images. `true` by default.
        ///
        /// Decompressing compressed image formats (such as JPEG) can significantly
        /// improve drawing performance as it allows a bitmap representation to be
        /// created in a background rather than on the main thread.
        public var isDecompressionEnabled = true
        #endif

        /// `true` by default. If `true` the pipeline will combine the requests
        /// with the same `loadKey` into a single request. The request only gets
        /// cancelled when all the registered requests are.
        public var isDeduplicationEnabled = true

        /// `true` by default. It `true` the pipeline will rate limits the requests
        /// to prevent trashing of the underlying systems (e.g. `URLSession`).
        /// The rate limiter only comes into play when the requests are started
        /// and cancelled at a high rate (e.g. scrolling through a collection view).
        public var isRateLimiterEnabled = true

        /// `false` by default. If `true` the pipeline will try to produce a new
        /// image each time it receives a new portion of data from data loader.
        /// The decoder used by the image loading session determines whether
        /// to produce a partial image or not.
        public var isProgressiveDecodingEnabled = false

        /// If the data task is terminated (either because of a failure or a
        /// cancellation) and the image was partially loaded, the next load will
        /// resume where it was left off. Supports both validators (`ETag`,
        /// `Last-Modified`). The resumable downloads are enabled by default.
        public var isResumableDataEnabled = true

        /// If `true` pipeline will detects GIFs and set `animatedImageData`
        /// (`UIImage` property). It will also disable processing of such images,
        /// and alter the way cache cost is calculated. However, this will not
        /// enable actual animated image rendering. To do that take a look at
        /// satellite projects (FLAnimatedImage and Gifu plugins for Nuke).
        /// `false` by default (to preserve resources).
        public static var isAnimatedImageDataEnabled = false

        /// Creates default configuration.
        /// - parameter dataLoader: `DataLoader()` by default.
        /// - parameter imageCache: `Cache.shared` by default.
        public init(dataLoader: DataLoading = DataLoader(), imageCache: ImageCaching? = ImageCache.shared) {
            self.dataLoader = dataLoader
            self.imageCache = imageCache

            self.dataLoadingQueue.maxConcurrentOperationCount = 6
            self.dataCachingQueue.maxConcurrentOperationCount = 2
            self.imageDecodingQueue.maxConcurrentOperationCount = 1
            self.imageProcessingQueue.maxConcurrentOperationCount = 2
        }
    }

    /// Initializes `ImagePipeline` instance with the given configuration.
    /// - parameter configuration: `Configuration()` by default.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.rateLimiter = RateLimiter(queue: queue)

        if configuration.isDeduplicationEnabled {
            processingTasks = [:]
            decodingTasks = [:]
            dataLoadingTasks = [:]
        }
    }

    public convenience init(_ configure: (inout ImagePipeline.Configuration) -> Void) {
        var configuration = ImagePipeline.Configuration()
        configure(&configuration)
        self.init(configuration: configuration)
    }

    // MARK: - Loading Images

    /// Loads an image with the given url.
    @discardableResult
    public func loadImage(with url: URL,
                          progress: ImageTask.ProgressHandler? = nil,
                          completion: ImageTask.Completion? = nil) -> ImageTask {
        return loadImage(with: ImageRequest(url: url), progress: progress, completion: completion)
    }

    /// Loads an image for the given request using image loading pipeline.
    @discardableResult
    public func loadImage(with request: ImageRequest,
                          progress: ImageTask.ProgressHandler? = nil,
                          completion: ImageTask.Completion? = nil) -> ImageTask {
        let task = makeImageTask(with: request)
        queue.async {
            // Start exeucing the task immediatelly.
            let delegate = ImageTaskAnonymousDelegate(progress: progress, completion: completion)
            task.delegate = delegate
            self.startTask(task, delegate: delegate)
        }
        return task
    }

    /// Creates a task with the given request and delegate. After the task
    /// is created, it needs to be started by calling `task.start()`.
    public func imageTask(with request: ImageRequest, delegate: ImageTaskDelegate) -> ImageTask {
        let task = makeImageTask(with: request)
        task.delegate = delegate
        return task
    }

    private func makeImageTask(with request: ImageRequest) -> ImageTask {
        let task = ImageTask(taskId: nextTaskId.increment(), request: request)
        task.pipeline = self
        return task
    }

    // MARK: - ImageTaskManaging

    func imageTaskStartCalled(_ task: ImageTask) {
        queue.async {
            self.startTask(task, delegate: nil)
        }
    }

    func imageTaskCancelCalled(_ task: ImageTask) {
        queue.async {
            task.isStartNeeded = false
            guard let context = self.tasks.removeValue(forKey: task) else { return }
            context.subscription?.unsubscribe()
        }
    }

    func imageTaskUpdatePriorityCalled(_ task: ImageTask, priority: ImageRequest.Priority) {
        queue.async {
            task.priority = priority
            guard let context = self.tasks[task] else { return }
            context.subscription?.setPriority(priority)
        }
    }

    // MARK: - Starting Image Tasks

    private final class ImageTaskExecutionContext {
        var subscription: TaskSubscription?
    }

    private func startTask(_ task: ImageTask, delegate anonymousDelegate: ImageTaskAnonymousDelegate?) {
        guard task.isStartNeeded else { return }
        task.isStartNeeded = false

        if self.didFinishCollectingMetrics != nil {
            task.metrics = ImageTaskMetrics(taskId: task.taskId, startDate: Date())
        }

        // Fast memory cache lookup. We do this asynchronously because we
        // expect users to check memory cache synchronously if needed.
        if task.request.memoryCacheOptions.isReadAllowed,
            let response = self.configuration.imageCache?.cachedResponse(for: task.request) {
            DispatchQueue.main.async {
                guard let delegate = task.delegate else { return }
                delegate.imageTask(task, didCompleteWithResponse: response, error: nil)
                _ = anonymousDelegate // retain anonymous delegates until we are finished with them
            }
            return
        }

        // Memory cache lookup failed -> start loading.
        if task.request.isDecodingDisabled {
            self.loadData(for: task, delegate: anonymousDelegate)
        } else {
            self.loadImage(for: task, delegate: anonymousDelegate)
        }
    }

    private func loadImage(for task: ImageTask, delegate anonymousDelegate: ImageTaskAnonymousDelegate?) {
        let request = task.request

        let context = ImageTaskExecutionContext()
        self.tasks[task] = context

        context.subscription = getProcessedImage(for: task.request)
            .subscribe(priority: task.priority) { [weak self, weak task] event in
                guard let self = self, let task = task else { return }

                if event.isCompleted {
                    self.tasks[task] = nil
                }

                // Store response in memory cache if allowed.
                if case let .value(response, isCompleted) = event, isCompleted && request.memoryCacheOptions.isWriteAllowed {
                    self.configuration.imageCache?.storeResponse(response, for: request)
                }

                DispatchQueue.main.async {
                    guard let delegate = task.delegate else { return }
                    switch event {
                    case let .value(response, isCompleted):
                        if isCompleted {
                            delegate.imageTask(task, didCompleteWithResponse: response, error: nil)
                        } else {
                            delegate.imageTask(task, didProduceProgressiveResponse: response)
                        }
                    case let .progress(progress):
                        task.completedUnitCount = progress.completed
                        task.totalUnitCount = progress.total
                        task._progress?.completedUnitCount = progress.completed
                        task._progress?.totalUnitCount = progress.total
                        delegate.imageTask(task, didUpdateProgress: progress.completed, totalUnitCount: progress.total)
                    case let .error(error):
                        delegate.imageTask(task, didCompleteWithResponse: nil, error: error)
                    }
                    _ = anonymousDelegate // retain anonymous delegates until we are finished with them
                }
        }
    }

    private func loadData(for task: ImageTask, delegate anonymousDelegate: ImageTaskAnonymousDelegate?) {
        let request = task.request

        let context = ImageTaskExecutionContext()
        self.tasks[task] = context

        context.subscription = getImageData(for: request)
            .subscribe(priority: task.priority) { [weak self, weak task] event in
            guard let self = self, let task = task else { return }

            guard event.isCompleted else {
                return
            }

            self.tasks[task] = nil

            DispatchQueue.main.async {
                guard let delegate = task.delegate else { return }
                // TODO: replace with separate completion handlers for decoding
                // For now we keep the behavior from the previous versions.
                delegate.imageTask(task, didCompleteWithResponse: nil, error: .decodingFailed)
                _ = anonymousDelegate // retain anonymous delegates until we are finished with them
            }
        }
    }

    // MARK: - Image Processing

    private typealias ImageProcessingTask = Task<ImageResponse, Error>

    private func getProcessedImage(for request: ImageRequest) -> ImageProcessingTask {
        let key = ImageRequest.ImageLoadKey(request: request)
        if let task = processingTasks?[key] {
            return task
        }

        let task = ImageProcessingTask(starter: { job in
            let task = self.getDecodedImage(for: request)
            job.dependency = task.subscribe { [weak self, weak job] event in
                guard let self = self, let job = job else { return }

                switch event {
                case let .value(image, isCompleted):
                    self.processImage(image, for: job, request: request, isCompleted: isCompleted)
                case let .progress(progress):
                    job.send(progress: progress)
                case let .error(error):
                    job.send(error: error)
                }
            }
        })

        processingTasks?[key] = task
        task.onDisposed = { [weak self] in
            self?.processingTasks?[key] = nil
        }
        return task
    }

    private func processImage(_ response: ImageResponse, for job: ImageProcessingTask.Job, request: ImageRequest, isCompleted: Bool) {
        guard let processor = self.processor(for: response.image, request: request) else {
            job.send(value: response, isCompleted: isCompleted) // No processing needed, send the decoded image
            return
        }

        if isCompleted {
            job.operation?.cancel() // Cancel any potential pending progressive processing tasks
        } else if job.operation != nil {
            return  // Back pressure - already processing another progressive image
        }

        let operation = BlockOperation { [weak self, weak job] in
            guard let self = self, let job = job else { return }

            let context = ImageProcessingContext(request: request, isFinal: isCompleted, scanNumber: response.scanNumber)
            let response = response.map { processor.process(image: $0, context: context) }

            self.queue.async {
                guard let response = response else {
                    if isCompleted {
                        job.send(error: .processingFailed)
                    } // Ignore when progressive processing fails
                    return
                }
                job.send(value: response, isCompleted: isCompleted)
            }
        }
        job.operation = operation
        configuration.imageProcessingQueue.addOperation(operation)
    }

    private func processor(for image: Image, request: ImageRequest) -> ImageProcessing? {
        if Configuration.isAnimatedImageDataEnabled && image.animatedImageData != nil {
            return nil // Don't process animated images.
        }
        var processors = [ImageProcessing]()
        if let processor = request.processor {
            processors.append(processor)
        }
        #if !os(macOS)
        if configuration.isDecompressionEnabled {
            processors.append(ImageDecompression())
        }
        #endif
        return processors.isEmpty ? nil : ImageProcessorComposition(processors)
    }

    // MARK: - Image Decoding

    private typealias ImageDecodingTask = Task<ImageResponse, Error>

    private final class ImageDecodingTaskContext {
        let request: ImageRequest
        var decoder: ImageDecoding?

        init(request: ImageRequest) {
            self.request = request
        }
    }

    private func getDecodedImage(for request: ImageRequest) -> ImageDecodingTask {
        let key = ImageRequest.LoadKey(request: request)
        if let task = decodingTasks?[key] {
            return task
        }

        let context = ImageDecodingTaskContext(request: request)

        let task = ImageDecodingTask(starter: { job in
            let task = self.getImageData(for: request)
            job.dependency = task.subscribe { [weak self, weak job] event in
                guard let self = self, let job = job else { return }

                switch event {
                case let .value((data, urlResponse), isCompleted):
                    self.decodeData(data, urlResponse: urlResponse, isCompleted: isCompleted, job: job, context: context)
                case let .progress(progress):
                    job.send(progress: progress)
                case let .error(error):
                    job.send(error: error)
                }
            }
        })

        decodingTasks?[key] = task
        task.onDisposed = { [weak self] in
            self?.decodingTasks?[key] = nil
        }

        return task
    }

    private func decodeData(_ data: Data, urlResponse: URLResponse?, isCompleted: Bool, job: ImageDecodingTask.Job, context: ImageDecodingTaskContext) {
        if isCompleted {
            job.operation?.cancel() // Cancel any potential pending progressive decoding tasks
        } else if !configuration.isProgressiveDecodingEnabled || job.operation != nil {
            return // Back pressure - already decoding another progressive data chunk
        }

        // Sanity check
        guard !data.isEmpty, let decoder = self.decoder(for: context, data: data, urlResponse: urlResponse) else {
            if isCompleted {
                job.send(error: .decodingFailed)
            }
            return
        }

        let operation = BlockOperation { [weak self, weak job] in
            guard let self = self, let job = job else { return }

            let image = autoreleasepool {
                decoder.decode(data: data, isFinal: isCompleted)
            }
            #if !os(macOS)
            if let image = image {
                ImageDecompression.setDecompressionNeeded(true, for: image)
            }
            #endif

            let scanNumber: Int? = (decoder as? ImageDecoder)?.numberOfScans

            self.queue.async {
                let response = image.map {
                    ImageResponse(image: $0, urlResponse: urlResponse, scanNumber: scanNumber)
                }
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
    private func decoder(for context: ImageDecodingTaskContext, data: Data, urlResponse: URLResponse?) -> ImageDecoding? {
        // Return the existing processor in case it has already been created.
        if let decoder = context.decoder {
            return decoder
        }

        let decoderContext = ImageDecodingContext(request: context.request, urlResponse: urlResponse, data: data)
        let decoder = configuration.imageDecoder(decoderContext)
        context.decoder = decoder
        return decoder
    }

    // MARK: - Data Loading

    private typealias ImageDataLoadingTask = Task<(Data, URLResponse?), Error>

    private final class ImageDataLoadingContext {
        let request: ImageRequest
        var urlResponse: URLResponse?
        var resumableData: ResumableData?
        var resumedDataCount: Int64 = 0
        lazy var data = Data()

        init(request: ImageRequest) {
            self.request = request
        }
    }

    private func getImageData(for request: ImageRequest) -> ImageDataLoadingTask {
        let key = ImageRequest.LoadKey(request: request)
        if let task = dataLoadingTasks?[key] {
            return task
        }

        let context = ImageDataLoadingContext(request: request)

        let task = ImageDataLoadingTask(starter: { task in
            if self.configuration.isRateLimiterEnabled {
                // Rate limiter is synchronized on pipeline's queue. Delayed work is
                // executed asynchronously also on this same queue.
                self.rateLimiter.execute { [weak self, weak task] in
                    guard let self = self, let task = task, !task.isDisposed else {
                        return false
                    }
                    self.loadImageDataFromCache(for: task, context: context)
                    return true
                }
            } else { // Start loading immediately.
                self.loadImageDataFromCache(for: task, context: context)
            }
        })

        dataLoadingTasks?[key] = task
        task.onDisposed = { [weak self] in
            self?.dataLoadingTasks?[key] = nil
        }
        return task
    }

    private func loadImageDataFromCache(for job: ImageDataLoadingTask.Job, context: ImageDataLoadingContext) {
        guard let cache = configuration.dataCache, let key = context.request.urlString else {
            loadImageData(for: job, context: context) // Skip disk cache lookup, load data
            return
        }

        let operation = BlockOperation { [weak self, weak job] in
            guard let self = self, let job = job else { return }
            let data = cache.cachedData(for: key)
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

    private func loadImageData(for job: ImageDataLoadingTask.Job, context: ImageDataLoadingContext) {
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
    private func loadImageData(for job: ImageDataLoadingTask.Job, context: ImageDataLoadingContext, finish: @escaping () -> Void) {
        guard !job.isDisposed else {
            return finish() // Task was cancelled by the time we got the chance to execute
        }

        var urlRequest = context.request.urlRequest

        // Read and remove resumable data from cache (we're going to insert it
        // back in the cache if the request fails to complete again).
        if configuration.isResumableDataEnabled,
            let resumableData = ResumableData.removeResumableData(for: urlRequest) {
            // Update headers to add "Range" and "If-Range" headers
            resumableData.resume(request: &urlRequest)
            // Save resumable data so that we could use it later (we need to
            // verify that server returns "206 Partial Content" before using it.
            context.resumableData = resumableData
        }

        let dataTask = configuration.dataLoader.loadData(
            with: urlRequest,
            didReceiveData: { [weak self, weak job] data, response in
                guard let self = self, let job = job else { return }
                self.queue.async {
                    self.imageDataLoadingJob(job, context: context, didReceiveData: data, response: response)
                }
            },
            completion: { [weak self, weak job] error in
                finish() // Finish the operation!
                guard let self = self, let job = job else { return }
                self.queue.async {
                    self.imageDataLoadingJob(job, context: context, didFinishLoadingDataWithError: error)
                }
        })

        job.onCancelled = { [weak self] in
            dataTask.cancel()
            finish() // Finish the operation!

            self?.tryToSaveResumableData(for: context)
        }
    }

    private func imageDataLoadingJob(_ job: ImageDataLoadingTask.Job, context: ImageDataLoadingContext, didReceiveData chunk: Data, response: URLResponse) {
        // Check if this is the first response.
        if context.urlResponse == nil {
            // See if the server confirmed that we can use the resumable data.
            if let resumableData = context.resumableData {
                if ResumableData.isResumedResponse(response) {
                    context.data = resumableData.data
                    context.resumedDataCount = Int64(resumableData.data.count)
                }
                context.resumableData = nil // Get rid of resumable data
            }
        }

        // Append data and save response
        context.data.append(chunk)
        context.urlResponse = response

        let progress = TaskProgress(completed: Int64(context.data.count), total: response.expectedContentLength + context.resumedDataCount)
        job.send(progress: progress)

        // Check if we haven't loaded an entire image yet. We give decoder
        // an opportunity to decide whether to decode this chunk or not.
        // In case `expectedContentLength` is undetermined (e.g. 0) we
        // don't allow progressive decoding.
        guard context.data.count < response.expectedContentLength else { return }

        job.send(value: (context.data, response))
    }

    private func imageDataLoadingJob(_ job: ImageDataLoadingTask.Job, context: ImageDataLoadingContext, didFinishLoadingDataWithError error: Swift.Error?) {
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
        if let dataCache = configuration.dataCache, let key = context.request.urlString {
            dataCache.storeData(context.data, for: key)
        }

        job.send(value: (context.data, context.urlResponse), isCompleted: true)
    }

    private func tryToSaveResumableData(for context: ImageDataLoadingContext) {
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
