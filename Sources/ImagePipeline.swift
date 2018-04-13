// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation

/// `ImagePipeline` implements an image loading pipeline. It loads image data using
/// data loader (`DataLoading`), then creates an image using `DataDecoding`
/// object, and transforms the image using processors (`Processing`) provided
/// in the `Request`.
///
/// Pipeline combines the requests with the same `loadKey` into a single request.
/// The request only gets cancelled when all the registered handlers are.
///
/// `ImagePipeline` limits the number of concurrent requests (the default maximum limit
/// is 6). It also rate limits the requests to prevent `Loader` from trashing
/// underlying systems (e.g. `URLSession`). The rate limiter only comes into play
/// when the requests are started and cancelled at a high rate (e.g. fast
/// scrolling through a collection view).
///
/// `ImagePipeline` features can be configured using `Loader.Options`.
///
/// `ImagePipeline` is thread-safe.
public /* final */ class ImagePipeline {
    public let configuration: Configuration

    // Image loading sessions. One or more tasks can be handled by the same session.
    private var sessions = [AnyHashable: Session]()

    // Synchornized access to sessions.
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Loader")

    private let rateLimiter = RateLimiter()

    /// Shared image pipeline.
    public static var shared = ImagePipeline()

    /// Some nitty-gritty options which can be used to customize loader.
    public struct Configuration {
        /// Data loader using by the pipeline.
        public var dataLoader: DataLoading

        public var dataLoadingQueue = OperationQueue()

        /// Data decoder used by the pipeline.
        public var dataDecoder: DataDecoding

        public var dataDecodingQueue = OperationQueue()

        /// Image cache used by the pipeline.
        public var imageCache: ImageCaching?

        /// Returns a processor for the given image and request. By default
        /// returns `request.processor`. Please keep in mind that you can
        /// override the processor from the request using this option but you're
        /// not going to override the processor used as a cache key.
        public var imageProcessor: (Image, ImageRequest) -> AnyImageProcessor? = { $1.processor }

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

        /// Creates default configuration.
        /// - parameter dataLoader: `DataLoader()` by default.
        /// - parameter dataDecoder: `DataDecoder()` by default.
        /// - parameter imageCache: `Cache.shared` by default.
        /// - parameter options: Options which can be used to customize loader.
        public init(dataLoader: DataLoading = DataLoader(), dataDecoder: DataDecoding = DataDecoder(), imageCache: ImageCaching? = ImageCache.shared) {
            self.dataLoader = dataLoader
            self.dataDecoder = dataDecoder
            self.imageCache = imageCache

            self.dataLoadingQueue.maxConcurrentOperationCount = 6
            self.dataDecodingQueue.maxConcurrentOperationCount = 1
            self.imageProcessingQueue.maxConcurrentOperationCount = 2
        }
    }

    /// Initializes `Loader` instance with the given loader, decoder.
    /// - parameter configuration: `Configuration()` by default.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public convenience init(_ configure: (inout ImagePipeline.Configuration) -> Void) {
        var configuration = ImagePipeline.Configuration()
        configure(&configuration)
        self.init(configuration: configuration)
    }

    // MARK: Loading Images

    public /* final */ class Task {
        // There might be a more performant solution
        fileprivate var cts = CancellationTokenSource()

        public typealias Completion = (Result<Image>) -> Void

        public func cancel() {
            cts.cancel()
        }
    }

    /// Loads an image with the given url.
    @discardableResult public func loadImage(with url: URL, completion: @escaping Task.Completion) -> Task {
        return loadImage(with: ImageRequest(url: url), completion: completion)
    }

    /// Loads an image for the given request using image loading pipeline.
    @discardableResult public func loadImage(with request: ImageRequest, completion: @escaping Task.Completion) -> Task {
        let task = Task()
        queue.async {
            guard !task.cts.isCancelling else { return } // Fast preflight check

            if let image = self.cachedImage(for: request) {
                DispatchQueue.main.async { completion(.success(image)) }
            } else {
                // Image not in cache - load an image.
                self._loadImage(request, task: task) { result in
                    if let image = result.value {
                        self.store(image: image, for: request)
                    }
                    DispatchQueue.main.async { completion(result) }
                }
            }
        }
        return task
    }
    
    private func _loadImage(_ request: ImageRequest, task: Task, completion: @escaping Task.Completion) {
        let session = _startSession(with: request)

        // Register handler with a session.
        let handler = Session.Handler(request: request, completion: completion)
        session.handlers.insert(handler)

        // Update data operation priority (in case it was already started).
        session.dataOperation?.queuePriority = session.priority.queuePriority

        task.cts.token.register { [weak self, weak session, weak handler] in
            guard let session = session, let handler = handler else { return }
            self?._cancelSession(session, handler: handler)
        }
    }

    // MARK: Managing Sessions

    private func _startSession(with request: ImageRequest) -> Session {
        // Check if session for the given key already exists.
        //
        // This part is more clever than I would like. The reason why we need a
        // key even when deduplication is disabled is to have a way to retain
        // a session by storing it in `sessions` dictionary.
        let key = configuration.isDeduplicationEnabled ? request.loadKey : UUID()
        if let session = sessions[key] {
            return session
        }
        let session = Session(request: request, key: key)
        sessions[key] = session
        _loadImage(for: session) // Start the pipeline
        return session
    }

    // Report progress to all registered handlers.
    private func _updateSessionProgress(completed: Int64, total: Int64, session: Session) {
        queue.async {
            #if swift(>=4.1)
            let handlers = session.handlers.compactMap { $0.request.progress }
            #else
            let handlers = session.handlers.flatMap { $0.request.progress }
            #endif
            guard !handlers.isEmpty else { return }
            DispatchQueue.main.async { handlers.forEach { $0(completed, total) } }
        }
    }

    // Report completion to all registered handlers.
    private func _completeSession(_ session: Session, result: Result<Image>) {
        queue.async {
            let handlers = session.handlers // Always non-empty at this point, no need to check
            handlers.forEach { $0.completion(result) }
            self._removeSession(session)
        }
    }

    // Cancel the session in case all handlers were removed.
    private func _cancelSession(_ session: Session, handler: Session.Handler) {
        queue.async {
            session.handlers.remove(handler)
            // Cancel the session when there are no handlers remaining.
            if session.handlers.isEmpty {
                session.cts.cancel()
                self._removeSession(session)
            }
        }
    }

    private func _removeSession(_ session: Session) {
        // Check in case we already started a new session for the same loading key.
        if sessions[session.key] === session {
            // By removing a session we get rid of all the stuff that is no longer
            // needed after completing associated tasks. This includes completion
            // and progress closures, individual requests, etc. The user may still
            // hold a reference to `ImagePipeline.Task` at this point, but it doesn't
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
            rateLimiter.execute(token: session.cts.token) { [weak self, weak session] in
                guard let session = session else { return }
                self?._loadData(for: session)
            }
        } else { // Start loading immediately.
            _loadData(for: session)
        }
    }

    private func _loadData(for session: Session) {
        let token = session.cts.token
        let request = session.request.urlRequest

        guard !token.isCancelling else { return } // Preflight check

        // Wrap data request in an operation to limit maximum number of
        // concurrent data tasks.
        let operation = Operation(starter: { [weak self, weak session] finish in
            self?.configuration.dataLoader.loadData(
                with: request,
                token: token,
                progress: {
                    guard let session = session else { return }
                    self?._updateSessionProgress(completed: $0, total: $1, session: session)
                },
                completion: {
                    finish()
                    guard let session = session else { return }
                    self?._didReceiveData($0, session: session)
            }
            )
            token.register(finish) // Make sure we always finish the operation.
        })

        // Synchronize access to `session`.
        queue.async {
            operation.queuePriority = session.priority.queuePriority
            self.configuration.dataLoadingQueue.addOperation(operation)
            token.register { [weak operation] in operation?.cancel() }
            session.dataOperation = operation
        }
    }

    private func _didReceiveData(_ result: Result<(Data, URLResponse)>, session: Session) {
        switch result {
        case let .success(val): _decode(response: val, session: session)
        case let .failure(err): _completeSession(session, result: .failure(err))
        }
    }

    private func _decode(response: (Data, URLResponse), session: Session) {
        let decode = { [decoder = self.configuration.dataDecoder] in
            decoder.decode(data: response.0, response: response.1)
        }
        configuration.dataLoadingQueue.addOperation { [weak self, weak session] in
            guard let session = session else { return }
            guard let image = autoreleasepool(invoking: decode) else {
                self?._completeSession(session, result: .failure(Error.decodingFailed))
                return
            }
            self?._process(image: image, session: session)
        }
    }

    private func _process(image: Image, session: Session) {
        // Check if processing is required, complete immediatelly if not.
        guard let processor = configuration.imageProcessor(image, session.request) else {
            _completeSession(session, result: .success(image))
            return
        }
        let operation = BlockOperation { [weak self, weak session] in
            guard let session = session else { return }
            let image = autoreleasepool { processor.process(image) }
            let result = image.map(Result.success) ?? .failure(Error.processingFailed)
            self?._completeSession(session, result: result)
        }
        session.cts.token.register { [weak operation] in operation?.cancel() }
        configuration.imageProcessingQueue.addOperation(operation)
    }

    // MARK: Memory Cache Helpers

    public func cachedImage(for request: ImageRequest) -> Image? {
        guard request.memoryCacheOptions.readAllowed else { return nil }
        return configuration.imageCache?[request]
    }

    public func store(image: Image, for request: ImageRequest) {
        guard request.memoryCacheOptions.writeAllowed else { return }
        configuration.imageCache?[request] = image
    }

    // MARK: Session

    /// A image loading session. During a lifetime of a session handlers can
    /// subscribe and unsubscribe to it.
    private final class Session {
        /// The original request with which the session was created.
        let request: ImageRequest
        let key: AnyHashable // loading key
        let cts = CancellationTokenSource()
        var handlers = Set<Handler>()
        weak var dataOperation: Operation?

        init(request: ImageRequest, key: AnyHashable) {
            self.request = request; self.key = key
        }

        final class Handler: Hashable {
            let request: ImageRequest
            let completion: Task.Completion

            init(request: ImageRequest, completion: @escaping Task.Completion) {
                self.request = request; self.completion = completion
            }

            static func ==(lhs: Handler, rhs: Handler) -> Bool {
                return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
            }

            var hashValue: Int {
                return ObjectIdentifier(self).hashValue
            }
        }

        var priority: ImageRequest.Priority {
            return handlers.map { $0.request.priority }.max() ?? .normal
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
