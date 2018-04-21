// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageTask

/// - important: Make sure that you access Task properties only from the
/// delegate queue.
public /* final */ class ImageTask: Hashable {
    public let taskId: Int
    public private(set) var request: ImageRequest

    public fileprivate(set) var completedUnitCount: Int64 = 0
    public fileprivate(set) var totalUnitCount: Int64 = 0

    public var completion: Completion?
    public var progressHandler: ProgressHandler?
    public var progressiveImageHandler: ProgressiveImageHandler?

    public typealias Completion = (_ result: Result<Image>) -> Void
    public typealias ProgressHandler = (_ completed: Int64, _ total: Int64) -> Void
    public typealias ProgressiveImageHandler = (_ image: Image) -> Void

    public fileprivate(set) var metrics: Metrics

    fileprivate weak private(set) var pipeline: ImagePipeline?
    fileprivate weak var session: ImagePipeline.Session?
    fileprivate var isCancelled = false

    public init(taskId: Int, request: ImageRequest, pipeline: ImagePipeline) {
        self.taskId = taskId
        self.request = request
        self.pipeline = pipeline
        self.metrics = Metrics(taskId: taskId, startDate: Date())
    }

    public func cancel() {
        pipeline?._imageTaskCancelled(self)
    }

    public func setPriority(_ priority: ImageRequest.Priority) {
        request.priority = priority
        pipeline?._imageTask(self, didUpdatePriority: priority)
    }

    public static func ==(lhs: ImageTask, rhs: ImageTask) -> Bool {
        return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    public var hashValue: Int {
        return ObjectIdentifier(self).hashValue
    }
}

// MARK: - ImagePipeline

/// `ImagePipeline` implements an image loading pipeline. It loads image data using
/// data loader (`DataLoading`), then creates an image using `DataDecoding`
/// object, and transforms the image using processors (`Processing`) provided
/// in the `Request`.
///
/// Pipeline combines the requests with the same `loadKey` into a single request.
/// The request only gets cancelled when all the registered handlers are.
///
/// `ImagePipeline` limits the number of concurrent requests (the default maximum limit
/// is 5). It also rate limits the requests to prevent `Loader` from trashing
/// underlying systems (e.g. `URLSession`). The rate limiter only comes into play
/// when the requests are started and cancelled at a high rate (e.g. fast
/// scrolling through a collection view).
///
/// `ImagePipeline` features can be configured using `Loader.Options`.
///
/// `ImagePipeline` is thread-safe.
public /* final */ class ImagePipeline {
    public let configuration: Configuration

    // This is a queue on which we access the sessions.
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.ImagePipeline")

    private let decodingQueue = DispatchQueue(label: "com.github.kean.Nuke.ImagePipeline.DecodingQueue")

    // Image loading sessions. One or more tasks can be handled by the same session.
    private var sessions = [AnyHashable: Session]()

    private var nextTaskId: Int32 = 0
    private var nextSessionId: Int32 = 0

    private let rateLimiter: RateLimiter

    /// Shared image pipeline.
    public static var shared = ImagePipeline()

    public struct Configuration {
        /// Data loader using by the pipeline.
        public var dataLoader: DataLoading

        public var dataLoadingQueue = OperationQueue()

        /// Default implementation uses shared `ImageDecoderRegistry` to create
        /// a decoder that matches the context.
        public var imageDecoder: (ImageDecodingContext) -> ImageDecoding = {
            return ImageDecoderRegistry.shared.decoder(for: $0)
        }

        /// Image cache used by the pipeline.
        public var imageCache: ImageCaching?

        /// Returns a processor for the context. By default simply returns
        /// `request.processor`. Please keep in mind that you can override the
        /// processor from the request using this option but you're not going
        /// to override the processor used as a cache key.
        public var imageProcessor: (ImageProcessingContext) -> AnyImageProcessor? = {
            return $0.request.processor
        }

        public var imageProcessingQueue = OperationQueue()

        /// `true` by default. If `true` loader combines the requests with the
        /// same `loadKey` into a single request. The request only gets cancelled
        /// when all the registered requests are.
        public var isDeduplicationEnabled = true

        /// `true` by default. It `true` loader rate limits the requests to
        /// prevent `Loader` from trashing underlying systems (e.g. `URLSession`).
        /// The rate limiter only comes into play when the requests are started
        /// and cancelled at a high rate (e.g. scrolling through a collection view).
        public var isRateLimiterEnabled = true

        /// `false` by default.
        public var isProgressiveDecodingEnabled = false

        /// `true` by default.
        public var isResumableDataEnabled = true

        /// Creates default configuration.
        /// - parameter dataLoader: `DataLoader()` by default.
        /// - parameter imageCache: `Cache.shared` by default.
        /// - parameter options: Options which can be used to customize loader.
        public init(dataLoader: DataLoading = DataLoader(), imageCache: ImageCaching? = ImageCache.shared) {
            self.dataLoader = dataLoader
            self.imageCache = imageCache

            self.dataLoadingQueue.maxConcurrentOperationCount = 6
            self.imageProcessingQueue.maxConcurrentOperationCount = 2
        }
    }

    /// Initializes `Loader` instance with the given loader, decoder.
    /// - parameter configuration: `Configuration()` by default.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.rateLimiter = RateLimiter(queue: queue)
    }

    public convenience init(_ configure: (inout ImagePipeline.Configuration) -> Void) {
        var configuration = ImagePipeline.Configuration()
        configure(&configuration)
        self.init(configuration: configuration)
    }

    // MARK: Loading Images

    /// Loads an image with the given url.
    @discardableResult public func loadImage(with url: URL, completion: @escaping ImageTask.Completion) -> ImageTask {
        return loadImage(with: ImageRequest(url: url), completion: completion)
    }

    /// Loads an image for the given request using image loading pipeline.
    @discardableResult public func loadImage(with request: ImageRequest, completion: @escaping ImageTask.Completion) -> ImageTask {
        let task = ImageTask(taskId: Int(OSAtomicIncrement32(&nextTaskId)), request: request, pipeline: self)
        task.completion = completion
        queue.async {
            guard !task.isCancelled else { return } // Fast preflight check
            self._startLoadingImage(for: task)
        }
        return task
    }

    private func _startLoadingImage(for task: ImageTask) {
        if let image = _cachedImage(for: task.request) {
            task.metrics.isMemoryCacheHit = true
            DispatchQueue.main.async {
                task.completion?(.success(image))
            }
            return
        }

        let session = _createSession(with: task.request)
        task.session = session

        task.metrics.session = session.metrics
        task.metrics.wasSubscibedToExistingSession = !session.tasks.isEmpty

        // Register handler with a session.
        session.tasks.insert(task)

        // Update data operation priority (in case it was already started).
        session.dataOperation?.queuePriority = session.priority.queuePriority
    }

    fileprivate func _imageTask(_ task: ImageTask, didUpdatePriority: ImageRequest.Priority) {
        queue.async {
            guard let session = task.session else { return }
            session.dataOperation?.queuePriority = session.priority.queuePriority
        }
    }

    // Cancel the session in case all handlers were removed.
    fileprivate func _imageTaskCancelled(_ task: ImageTask) {
        queue.async {
            guard !task.isCancelled else { return }
            task.isCancelled = true

            task.metrics.wasCancelled = true
            task.metrics.endDate = Date()

            guard let session = task.session else { return } // executing == true
            session.tasks.remove(task)
            // Cancel the session when there are no remaining tasks.
            if session.tasks.isEmpty {
                self._tryToSaveResumableData(for: session)
                self._removeSession(session)
                session.cts.cancel()

                session.metrics.wasCancelled = true
                session.metrics.endDate = Date()
            }
        }
    }

    // MARK: Managing Sessions

    private func _createSession(with request: ImageRequest) -> Session {
        // Check if session for the given key already exists.
        //
        // This part is more clever than I would like. The reason why we need a
        // key even when deduplication is disabled is to have a way to retain
        // a session by storing it in `sessions` dictionary.
        let key = configuration.isDeduplicationEnabled ? request.loadKey : UUID()
        if let session = sessions[key] {
            return session
        }
        let session = Session(sessionId: Int(OSAtomicIncrement32(&nextSessionId)), request: request, key: key)
        sessions[key] = session
        _loadImage(for: session) // Start the pipeline
        return session
    }

    private func _removeSession(_ session: Session) {
        // Check in case we already started a new session for the same loading key.
        if sessions[session.key] === session {
            // By removing a session we get rid of all the stuff that is no longer
            // needed after completing associated tasks. This includes completion
            // and progress closures, individual requests, etc. The user may still
            // hold a reference to `ImageTask` at this point, but it doesn't
            // store almost anythng.
            sessions[session.key] = nil
        }
    }

    // MARK: Image Pipeline
    //
    // This is where the images actually get loaded.

    private func _loadImage(for session: Session) {
        // Use rate limiter to prevent trashing of the underlying systems
        if configuration.isRateLimiterEnabled {
            // Rate limiter is synchronized on pipeline's queue. Delayed work is
            // executed asynchronously also on this same queue.
            rateLimiter.execute(token: session.cts.token) { [weak self, weak session] in
                guard let session = session else { return }
                self?._loadData(for: session)
            }
        } else { // Start loading immediately.
            _loadData(for: session)
        }
    }

    private func _loadData(for session: Session) {
        guard !session.token.isCancelling else { return } // Preflight check

        // Wrap data request in an operation to limit maximum number of
        // concurrent data tasks.
        let operation = Operation(starter: { [weak self, weak session] finish in
            guard let session = session else { finish(); return }
            self?.queue.async {
                self?._actuallyLoadData(for: session, finish: finish)
            }
        })

        operation.queuePriority = session.priority.queuePriority
        self.configuration.dataLoadingQueue.addOperation(operation)
        session.token.register { [weak operation] in operation?.cancel() }

        session.dataOperation = operation
    }

    // This methods gets called inside data loading operation (Operation).
    private func _actuallyLoadData(for session: Session, finish: @escaping () -> Void) {
        session.metrics.dataLoadingStartDate = Date()

        var urlRequest = session.request.urlRequest

        // Read and remove resumable data from cache (we're going to insert it
        // back in the cache if the request fails to complete again).
        if configuration.isResumableDataEnabled,
            let resumableData = ResumableData.removeResumableData(for: urlRequest) {
            // Update headers to add "Range" and "If-Range" headers
            resumableData.resume(request: &urlRequest)
            // Save resumable data so that we could use it later (we need to
            // verify that server returns "206 Partial Content" before using it.
            session.resumableData = resumableData

            // Collect metrics
            session.metrics.wasResumed = true
            session.metrics.resumedDataCount = resumableData.data.count
        }

        let task = configuration.dataLoader.loadData(
            with: urlRequest,
            didReceiveData: { [weak self, weak session] (data, response) in
                self?.queue.async {
                    guard let session = session else { return }
                    self?._session(session, didReceiveData: data, response: response)
                }
            },
            completion: { [weak self, weak session] (error) in
                finish() // Important! Mark Operation as finished.
                self?.queue.async {
                    guard let session = session else { return }
                    self?._session(session, didFinishLoadingDataWithError: error)
                }
        })
        session.token.register {
            task.cancel()
            finish() // Make sure we always finish the operation.
        }
    }

    private func _session(_ session: Session, didReceiveData chunk: Data, response: URLResponse) {
        // Check if this is the first response.
        if session.urlResponse == nil {
            // See if the server confirmed that we can use the resumable data.
            if let resumableData = session.resumableData {
                if ResumableData.isResumedResponse(response) {
                    session.data = resumableData.data
                    session.metrics.serverConfirmedResume = true
                }
                session.resumableData = nil // Get rid of resumable data anyway
            }
        }

        // Append data and save response
        session.data.append(chunk)
        session.urlResponse = response

        // Collect metrics
        session.metrics.downloadedDataCount = ((session.metrics.downloadedDataCount ?? 0) + chunk.count)

        // Update tasks' progress and call progress closures if any
        let (completed, total) = (Int64(session.data.count), response.expectedContentLength)
        let tasks = session.tasks
        DispatchQueue.main.async {
            for task in tasks { // We access tasks only on main thread
                (task.completedUnitCount, task.totalUnitCount) = (completed, total)
                task.progressHandler?(completed, total)
            }
        }

        // Check if progressive decoding is enabled (disabled by default)
        if configuration.isProgressiveDecodingEnabled {
            // Check if we haven't loaded an entire image yet. We give decoder
            // an opportunity to decide whether to decode this chunk or not.
            // In case `expectedContentLength` is undetermined (e.g. 0) we
            // don't allow progressive decoding.
            guard session.data.count < response.expectedContentLength else { return }

            _decodePartialImage(for: session)
        }
    }

    private func _decodePartialImage(for session: Session) {
        guard let decoder = _decoder(for: session) else { return }
        let data = session.data
        decodingQueue.async { [weak self, weak session] in
            guard let session = session else { return }

            // Produce partial image
            guard let image = decoder.decode(data: data, isFinal: false) else { return }
            let scanNumber: Int? = (decoder as? ImageDecoder)?.numberOfScans // Need a public way to implement this.
            self?.queue.async {
                self?._session(session, didDecodePartialImage: image, scanNumber: scanNumber)
            }
        }
    }

    // Lazily creates a decoder if necessary.
    private func _decoder(for session: Session) -> ImageDecoding? {
        // Return existing one.
        if let decoder = session.decoder { return decoder }

        // Basic sanity checks.
        guard let response = session.urlResponse, !session.data.isEmpty else { return nil }

        let context = ImageDecodingContext(request: session.request, urlResponse: response, data: session.data)
        let decoder = configuration.imageDecoder(context)
        session.decoder = decoder
        return decoder
    }

    private func _session(_ session: Session, didFinishLoadingDataWithError error: Swift.Error?) {
        session.metrics.dataLoadingEndDate = Date()

        guard error == nil else {
            _tryToSaveResumableData(for: session)
            _session(session, completedWith: .failure(error ?? Error.decodingFailed))
            return
        }

        // Basic sanity checks.
        guard !session.data.isEmpty, let decoder = _decoder(for: session) else {
            _session(session, completedWith: .failure(error ?? Error.decodingFailed))
            return
        }

        let data = session.data
        session.data.removeAll() // We no longer need the data stored in session.

        let metrics = session.metrics

        decodingQueue.async { [weak self, weak session] in
            guard let session = session else { return }
            metrics.decodingStartDate = Date()
            // Produce final image
            let image = autoreleasepool {
                decoder.decode(data: data, isFinal: true)
            }
            metrics.decodingEndDate = Date()
            self?.queue.async {
                self?._session(session, didDecodeImage: image)
            }
        }
    }

    private func _tryToSaveResumableData(for session: Session) {
        // Try to save resumable data in case the task was cancelled
        // (`URLError.cancelled`) or failed to complete with other error.
        if configuration.isResumableDataEnabled,
            let response = session.urlResponse, !session.data.isEmpty,
            let resumableData = ResumableData(response: response, data: session.data) {
            ResumableData.storeResumableData(resumableData, for: session.request.urlRequest)
        }
    }

    private func _session(_ session: Session, didDecodePartialImage image: Image, scanNumber: Int?) {
        // Producing faster than able to consume, skip this partial.
        // As an alternative we could store partial in a buffer for later, but
        // this is an option which is simpler to implement.
        guard session.processingPartialOperation == nil else { return }

        let context = ImageProcessingContext(image: image, request: session.request, isFinal: false, scanNumber: scanNumber)
        guard let processor = configuration.imageProcessor(context) else {
            _session(session, didProducePartialImage: image)
            return
        }

        let operation = BlockOperation { [weak self, weak session] in
            guard let session = session else { return }
            let image = autoreleasepool { processor.process(image) }
            self?.queue.async {
                session.processingPartialOperation = nil
                if let image = image {
                    self?._session(session, didProducePartialImage: image)
                }
            }
        }
        session.processingPartialOperation = operation
        configuration.imageProcessingQueue.addOperation(operation)
    }

    private func _session(_ session: Session, didDecodeImage image: Image?) {
        session.decoder = nil // Decoding session completed, no longer need decoder.
        session.metrics.decodingEndDate = Date()

        guard let image = image else {
            _session(session, completedWith: .failure(Error.decodingFailed))
            return
        }

        // Check if processing is required, complete immediatelly if not.
        let context = ImageProcessingContext(image: image, request: session.request, isFinal: true, scanNumber: nil)
        guard let processor = configuration.imageProcessor(context) else {
            _session(session, completedWith: .success(image))
            return
        }

        let metrics = session.metrics

        let operation = BlockOperation { [weak self, weak session] in
            guard let session = session else { return }
            metrics.processingStartDate = Date()
            let image = autoreleasepool { processor.process(image) }
            let result = image.map(Result.success) ?? .failure(Error.processingFailed)
            metrics.processingEndDate = Date()
            self?.queue.async {
                session.metrics.processingEndDate = Date()
                self?._session(session, completedWith: result)
            }
        }
        session.cts.token.register { [weak operation] in operation?.cancel() }
        configuration.imageProcessingQueue.addOperation(operation)
    }

    private func _session(_ session: Session, didProducePartialImage image: Image) {
        // Check if we haven't completed the session yet by producing a final image.
        guard !session.isCompleted else { return }
        let tasks = session.tasks
        DispatchQueue.main.async {
            for task in tasks {
                task.progressiveImageHandler?(image)
            }
        }
    }

    private func _session(_ session: Session, completedWith result: Result<Image>) {
        if let image = result.value {
            _store(image: image, for: session.request)
        }
        session.isCompleted = true
        session.metrics.endDate = Date()

        // Cancel any outstanding parital processing.
        session.processingPartialOperation?.cancel()

        let tasks = session.tasks
        tasks.forEach { $0.metrics.endDate = Date() }
        DispatchQueue.main.async {
            for task in tasks {
                task.completion?(result)
            }
        }
        _removeSession(session)
    }

    // MARK: Memory Cache Helpers

    private func _cachedImage(for request: ImageRequest) -> Image? {
        guard request.memoryCacheOptions.readAllowed else { return nil }
        return configuration.imageCache?[request]
    }

    private func _store(image: Image, for request: ImageRequest) {
        guard request.memoryCacheOptions.writeAllowed else { return }
        configuration.imageCache?[request] = image
    }

    // MARK: Session

    /// A image loading session. During a lifetime of a session handlers can
    /// subscribe to and unsubscribe from it.
    fileprivate final class Session {
        let sessionId: Int
        var isCompleted: Bool = false // there is probably a way to remote this

        /// The original request with which the session was created.
        let request: ImageRequest
        let key: AnyHashable // loading key
        let cts = _CancellationTokenSource()
        var token: _CancellationToken { return cts.token }

        // Registered image tasks.
        var tasks = Set<ImageTask>()

        // Data loading session.
        weak var dataOperation: Foundation.Operation?
        var urlResponse: URLResponse?
        var resumableData: ResumableData?
        lazy var data = Data()

        // Decoding session.
        var decoder: ImageDecoding?

        // Progressive decoding.
        var processingPartialOperation: Foundation.Operation?

        // Metrics that we collect during the lifetime of a session.
        let metrics: ImageTask.Metrics.SessionMetrics

        init(sessionId: Int, request: ImageRequest, key: AnyHashable) {
            self.sessionId = sessionId
            self.request = request
            self.key = key
            self.metrics = ImageTask.Metrics.SessionMetrics(sessionId: sessionId)
        }

        var priority: ImageRequest.Priority {
            return tasks.map { $0.request.priority }.max() ?? .normal
        }
    }

    // MARK: Errors

    /// Error returns by `Loader` class itself. `Loader` might also return
    /// errors from underlying `DataLoading` object.
    public enum Error: Swift.Error, CustomDebugStringConvertible {
        case decodingFailed
        case processingFailed

        public var debugDescription: String {
            switch self {
            case .decodingFailed: return "Failed to create an image from the image data"
            case .processingFailed: return "Failed to process the image"
            }
        }
    }
}

// MARK - Metrics

extension ImageTask {
    public final class Metrics: CustomDebugStringConvertible {
        public let taskId: Int
        public fileprivate(set) var wasCancelled: Bool = false
        public fileprivate(set) var session: SessionMetrics?

        public let startDate: Date
        public fileprivate(set) var endDate: Date? // failed or completed
        public var totalDuration: TimeInterval? {
            guard let endDate = endDate else { return nil }
            return endDate.timeIntervalSince(startDate)
        }

        /// Returns `true` is the task wasn't the one that initiated image loading.
        public fileprivate(set) var wasSubscibedToExistingSession: Bool = false
        public fileprivate(set) var isMemoryCacheHit: Bool = false

        init(taskId: Int, startDate: Date) {
            self.taskId = taskId; self.startDate = startDate
        }

        public var debugDescription: String {
            var printer = Printer()
            printer.section(title: "Task Information") {
                $0.value("Task ID", taskId)
                $0.value("Total Duration", Printer.duration(totalDuration))
                $0.value("Was Cancelled", wasCancelled)
                $0.value("Is Memory Cache Hit", isMemoryCacheHit)
                $0.value("Was Subscribed To Existing Image Loading Session", wasSubscibedToExistingSession)
            }
            printer.section(title: "Timeline") {
                $0.timeline("Start Date", startDate)
                $0.timeline("End Date", endDate)
            }
            printer.section(title: "Image Loading Session") {
                $0.string(session.map({ $0.debugDescription }) ?? "nil")
            }
            return printer.output()
        }

        // Download session metrics. One more more tasks can share the same
        // session metrics.
        public final class SessionMetrics: CustomDebugStringConvertible {
            /// - important: Data loading might start prior to `timeResumed` if the task gets
            /// coalesced with another task.
            public let sessionId: Int
            public fileprivate(set) var wasCancelled: Bool = false

            // MARK: - Timeline

            public let startDate = Date()

            public fileprivate(set) var dataLoadingStartDate: Date?
            public fileprivate(set) var dataLoadingEndDate: Date?

            public fileprivate(set) var decodingStartDate: Date?
            public fileprivate(set) var decodingEndDate: Date?

            public fileprivate(set) var processingStartDate: Date?
            public fileprivate(set) var processingEndDate: Date?

            public fileprivate(set) var endDate: Date? // failed or completed

            public var totalDuration: TimeInterval? {
                guard let endDate = endDate else { return nil }
                return endDate.timeIntervalSince(startDate)
            }

            // MARK: - Resumable Data

            public fileprivate(set) var wasResumed: Bool?
            public fileprivate(set) var resumedDataCount: Int?
            public fileprivate(set) var serverConfirmedResume: Bool?

            public fileprivate(set) var downloadedDataCount: Int?
            public var totalDownloadedDataCount: Int? {
                guard let downloaded = self.downloadedDataCount else { return nil }
                return downloaded + (resumedDataCount ?? 0)
            }

            init(sessionId: Int) { self.sessionId = sessionId }

            public var debugDescription: String {
                var printer = Printer()
                printer.section(title: "Session Information") {
                    $0.value("Session ID", sessionId)
                    $0.value("Total Duration", Printer.duration(totalDuration))
                    $0.value("Was Cancelled", wasCancelled)
                }
                printer.section(title: "Timeline") {
                    $0.timeline("Start Date", startDate)
                    $0.timeline("Data Loading Start Date", dataLoadingStartDate)
                    $0.timeline("Data Loading End Date", dataLoadingEndDate)
                    $0.timeline("Decoding Start Date", decodingStartDate)
                    $0.timeline("Decoding End Date", decodingEndDate)
                    $0.timeline("Processing Start Date", processingStartDate)
                    $0.timeline("Processing End Date", processingEndDate)
                    $0.timeline("End Date", endDate)
                }
                printer.section(title: "Resumable Data") {
                    $0.value("Was Resumed", wasResumed)
                    $0.value("Resumable Data Count", resumedDataCount)
                    $0.value("Server Confirmed Resume", serverConfirmedResume)
                }
                return printer.output()
            }
        }
    }
}

// MARK: - Contexts

/// Image decoding context used when selecting which decoder to use.
public struct ImageDecodingContext {
    public let request: ImageRequest
    public let urlResponse: URLResponse
    public let data: Data
}

/// Image processing context used when selecting which processor to use.
public struct ImageProcessingContext {
    public let image: Image
    public let request: ImageRequest
    public let isFinal: Bool
    public let scanNumber: Int? // need a more general purpose way to implement this
}
