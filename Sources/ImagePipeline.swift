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
public /* final */ class ImagePipeline {
    public let configuration: Configuration

    // This is a queue on which we access the sessions.
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.ImagePipeline")

    private var tasks = [ImageTask: TaskSubscription]()

    private var processedImageFetchTasks: [AnyHashable: ProcessedImageFetchTask]?
    private var originalImageFetchTasks: [AnyHashable: OriginalImageFetchTask]?
    private var originalImageDataFetchTasks: [AnyHashable: OriginalImageDataFetchTask]?

    private var nextTaskId = Atomic<Int>(0)

    private let rateLimiter: RateLimiter

    /// Shared image pipeline.
    public static var shared = ImagePipeline()

    /// The closure that gets called each time the task is completed (or cancelled).
    /// Guaranteed to be called on the main thread.
    public var didFinishCollectingMetrics: ((ImageTask, ImageTaskMetrics) -> Void)?

    /// Initializes `ImagePipeline` instance with the given configuration.
    /// - parameter configuration: `Configuration()` by default.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.rateLimiter = RateLimiter(queue: queue)

        if configuration.isDeduplicationEnabled {
            processedImageFetchTasks = [:]
            originalImageFetchTasks = [:]
            originalImageDataFetchTasks = [:]
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
        let delegate = ImageTaskAnonymousDelegate(progress: progress, completion: completion)
        let task = imageTask(with: request, delegate: delegate)
        queue.async {
            self.startImageTask(task, delegate: delegate)
        }
        return task
    }

    /// Creates a task with the given request and delegate. After the task
    /// is created, it needs to be started by calling `task.start()`.
    public func imageTask(with request: ImageRequest, delegate: ImageTaskDelegate) -> ImageTask {
        let task = ImageTask(taskId: nextTaskId.increment(), request: request)
        task.pipeline = self
        task.delegate = delegate
        return task
    }

    // MARK: - Loading Image Data

    @discardableResult
    public func loadData(with request: ImageRequest,
                         progress: ((_ completed: Int64, _ total: Int64) -> Void)? = nil,
                         completion: @escaping (Result<(data: Data, response: URLResponse?), ImagePipeline.Error>) -> Void) -> ImageTask {
        let task = imageTask(with: request, delegate: dataTaskDummyDelegate)
        queue.async {
            self.startDataTask(task, progress: progress, completion: completion)
        }
        return task
    }

    // This is a bit of a hack to support new `loadData` feature. By setting delegate
    // to nil we indicate that the task is cancelled and no events must by delivered
    // to the client. We use the same logic for data tasks.
    private var dataTaskDummyDelegate = ImageTaskAnonymousDelegate(progress: nil, completion: nil)

    // MARK: - Image Task Events

    func imageTaskStartCalled(_ task: ImageTask) {
        queue.async {
            self.startImageTask(task, delegate: nil)
        }
    }

    func imageTaskCancelCalled(_ task: ImageTask) {
        queue.async {
            task.isStartNeeded = false
            guard let subscription = self.tasks.removeValue(forKey: task) else { return }
            subscription.unsubscribe()
        }
    }

    func imageTaskUpdatePriorityCalled(_ task: ImageTask, priority: ImageRequest.Priority) {
        queue.async {
            task.priority = priority
            guard let subscription = self.tasks[task] else { return }
            subscription.setPriority(priority)
        }
    }

    // MARK: - Starting Image Tasks

    private func startImageTask(_ task: ImageTask, delegate anonymousDelegate: ImageTaskAnonymousDelegate?) {
        guard task.isStartNeeded else { return }
        task.isStartNeeded = false

        if self.didFinishCollectingMetrics != nil {
            task.metrics = ImageTaskMetrics(taskId: task.taskId, startDate: Date())
        }

        // Fast memory cache lookup. We do this asynchronously because we
        // expect users to check memory cache synchronously if needed.
        if task.request.options.memoryCacheOptions.isReadAllowed,
            let response = self.configuration.imageCache?.cachedResponse(for: task.request) {
            DispatchQueue.main.async {
                guard let delegate = task.delegate else { return }
                delegate.imageTask(task, didCompleteWithResult: .success(response))
                _ = anonymousDelegate // retain anonymous delegates until we are finished with them
            }
            return
        }

        self.tasks[task] = getProcessedImage(for: task.request).subscribe(priority: task.priority) { [weak self, weak task] event in
            guard let self = self, let task = task else { return }

            if event.isCompleted {
                self.tasks[task] = nil
            }

            // Store response in memory cache if allowed.
            let request = task.request
            if case let .value(response, isCompleted) = event, isCompleted && request.options.memoryCacheOptions.isWriteAllowed {
                self.configuration.imageCache?.storeResponse(response, for: request)
            }

            DispatchQueue.main.async {
                guard let delegate = task.delegate else { return }
                switch event {
                case let .value(response, isCompleted):
                    if isCompleted {
                        delegate.imageTask(task, didCompleteWithResult: .success(response))
                    } else {
                        delegate.imageTask(task, didProduceProgressiveResponse: response)
                    }
                case let .progress(progress):
                    task.setProgress(progress)
                    delegate.imageTask(task, didUpdateProgress: progress.completed, totalUnitCount: progress.total)
                case let .error(error):
                    delegate.imageTask(task, didCompleteWithResult: .failure(error))
                }
                _ = anonymousDelegate // retain anonymous delegates until we are finished with them
            }
        }
    }

    private func startDataTask(_ task: ImageTask,
                               progress progressHandler: ((_ completed: Int64, _ total: Int64) -> Void)?,
                               completion: @escaping (Result<(data: Data, response: URLResponse?), ImagePipeline.Error>) -> Void) {
        if self.didFinishCollectingMetrics != nil {
            task.metrics = ImageTaskMetrics(taskId: task.taskId, startDate: Date())
        }

        self.tasks[task] = getImageData(for: task.request) .subscribe(priority: task.priority) { [weak self, weak task] event in
            guard let self = self, let task = task else { return }

            if event.isCompleted {
                self.tasks[task] = nil
            }

            DispatchQueue.main.async {
                guard let _ = task.delegate else { return }

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

    // MARK: - Get Processed Image

    private typealias ProcessedImageFetchTask = Task<ImageResponse, Error>

    private func getProcessedImage(for request: ImageRequest) -> ProcessedImageFetchTask {
        let key = ImageRequest.ImageLoadKey(request: request)
        if let task = processedImageFetchTasks?[key] {
            return task
        }

        let task = ProcessedImageFetchTask(starter: { job in
            self.loadProcessedImage(for: request, job: job)
        })

        processedImageFetchTasks?[key] = task
        task.onDisposed = { [weak self] in
            self?.processedImageFetchTasks?[key] = nil
        }
        return task
    }

    private func loadProcessedImage(for request: ImageRequest, job: ProcessedImageFetchTask.Job) {
        guard !request.processors.isEmpty, let dataCache = configuration.dataCache, configuration.isDataCacheForProcessedDataEnabled else {
            loadOriginaImage(for: request, job: job)
            return
        }

        let key = (request.urlString ?? "") + ImageProcessorComposition(request.processors).identifier

        let operation = BlockOperation { [weak self, weak job] in
            guard let self = self, let job = job else { return }
            let data = dataCache.cachedData(for: key)
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
            let response = decoder.decode(data, urlResponse: nil, isFinal: true)
            self.queue.async {
                if let response = response {
                    self.decompressProcessedImage(response, isCompleted: true, for: request, job: job)
                } else {
                    self.loadOriginaImage(for: request, job: job)
                }
            }
        }
        job.operation = operation
        configuration.imageDecodingQueue.addOperation(operation)
    }

    private func decompressProcessedImage(_ response: ImageResponse, isCompleted: Bool, for request: ImageRequest, job: ProcessedImageFetchTask.Job) {
        #if os(macOS)
        job.send(value: response, isCompleted: isCompleted) // There is no decompression on macOS
        #else
        guard configuration.isDecompressionEnabled &&
            ImageDecompressor.isDecompressionNeeded(for: response.image) ?? false &&
            !(Configuration.isAnimatedImageDataEnabled && response.image.animatedImageData != nil) else {
            job.send(value: response, isCompleted: isCompleted)
            return
        }

        if isCompleted {
            job.operation?.cancel() // Cancel any potential pending progressive decompression tasks
        } else if job.operation != nil {
            return  // Back pressure - already processing another progressive image
        }

        guard !job.isDisposed else { return }

        let operation = BlockOperation { [weak self, weak job] in
            guard let self = self, let job = job else { return }

            let response = response.map { ImageDecompressor().decompress(image: $0) } ?? response

            self.queue.async {
                job.send(value: response, isCompleted: isCompleted)
            }
        }
        job.operation = operation
        configuration.imageDecompressingQueue.addOperation(operation)
        #endif
    }

    private func loadOriginaImage(for request: ImageRequest, job: ProcessedImageFetchTask.Job) {
        guard !job.isDisposed else { return }

        let task = self.getDecodedImage(for: request)
        job.dependency = task.subscribe { [weak self, weak job] event in
            guard let self = self, let job = job else { return }
            switch event {
            case let .value(image, isCompleted):
                self.processImage(image, isCompleted: isCompleted, for: request, job: job)
            case let .progress(progress):
                job.send(progress: progress)
            case let .error(error):
                job.send(error: error)
            }
        }
    }

    private func processImage(_ response: ImageResponse, isCompleted: Bool, for request: ImageRequest, job: ProcessedImageFetchTask.Job) {
        guard let processor = self.processor(for: response.image, request: request) else {
            decompressProcessedImage(response, isCompleted: isCompleted, for: request, job: job) // No processing needed
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
                if isCompleted {
                    self.storeProcessedImageInDataCache(response, request: request)
                }
                job.operation = nil // Clear operation so that decompression can run
                self.decompressProcessedImage(response, isCompleted: isCompleted, for: request, job: job)
            }
        }
        job.operation = operation
        configuration.imageProcessingQueue.addOperation(operation)
    }

    private func storeProcessedImageInDataCache(_ response: ImageResponse, request: ImageRequest) {
        guard let dataCache = configuration.dataCache, configuration.isDataCacheForProcessedDataEnabled else {
            return
        }
        let context = ImageEncodingContext(request: request, image: response.image, urlResponse: response.urlResponse)
        let encoder = configuration.makeImageEncoder(context)
        configuration.imageEncodingQueue.addOperation {
            guard let data = encoder.encode(image: response.image) else {
                return
            }
            let key = (request.urlString ?? "") + ImageProcessorComposition(request.processors).identifier
            dataCache.storeData(data, for: key) // This is instant
        }
    }

    private func processor(for image: Image, request: ImageRequest) -> ImageProcessing? {
        if Configuration.isAnimatedImageDataEnabled && image.animatedImageData != nil {
            return nil // Don't process animated images.
        }
        let processors = request.processors
        return processors.isEmpty ? nil : ImageProcessorComposition(processors)
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

    private func getDecodedImage(for request: ImageRequest) -> OriginalImageFetchTask {
        let key = ImageRequest.LoadKey(request: request)
        if let task = originalImageFetchTasks?[key] {
            return task
        }

        let context = OriginalImageFetchContext(request: request)

        let task = OriginalImageFetchTask(starter: { job in
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

        originalImageFetchTasks?[key] = task
        task.onDisposed = { [weak self] in
            self?.originalImageFetchTasks?[key] = nil
        }

        return task
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
            let response = decoder.decode(data, urlResponse: urlResponse, isFinal: isCompleted)
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

    private func getImageData(for request: ImageRequest) -> OriginalImageDataFetchTask {
        let key = ImageRequest.LoadKey(request: request)
        if let task = originalImageDataFetchTasks?[key] {
            return task
        }

        let context = OriginalImageDataFetchContext(request: request)

        let task = OriginalImageDataFetchTask(starter: { task in
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

        originalImageDataFetchTasks?[key] = task
        task.onDisposed = { [weak self] in
            self?.originalImageDataFetchTasks?[key] = nil
        }
        return task
    }

    private func loadImageDataFromCache(for job: OriginalImageDataFetchTask.Job, context: OriginalImageDataFetchContext) {
        guard let cache = configuration.dataCache, configuration.isDataCacheForOriginalDataEnabled, let key = context.request.urlString else {
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

    private func imageDataLoadingJob(_ job: OriginalImageDataFetchTask.Job, context: OriginalImageDataFetchContext, didReceiveData chunk: Data, response: URLResponse) {
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
        if let dataCache = configuration.dataCache, configuration.isDataCacheForOriginalDataEnabled, let key = context.request.urlString {
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
