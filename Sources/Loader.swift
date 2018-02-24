// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Loads images.
public protocol Loading {
    /// Loads an image with the given request.
    ///
    /// Loader doesn't make guarantees on which thread the completion closure is
    /// called and whether it gets called when the operation is cancelled.
    func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void)
}

public typealias ProgressHandler = (_ completed: Int64, _ total: Int64) -> Void
private typealias Completion = (Result<Image>) -> Void

public extension Loading {
    /// Loads an image with the given request.
    public func loadImage(with request: Request, completion: @escaping (Result<Image>) -> Void) {
        loadImage(with: request, token: nil, completion: completion)
    }

    /// Loads an image with the given url.
    public func loadImage(with url: URL, token: CancellationToken? = nil, completion: @escaping (Result<Image>) -> Void) {
        loadImage(with: Request(url: url), token: token, completion: completion)
    }
}

/// `Loader` implements an image loading pipeline. It loads image data using
/// data loader (`DataLoading`), then creates an image using `DataDecoding`
/// object, and transforms the image using processors (`Processing`) provided
/// in the `Request`.
///
/// Loader combines the requests with the same `loadKey` into a single request.
/// The request only gets cancelled when all the registered handlers are.
///
/// `Loader` limits the number of concurrent requests (the default maximum limit
/// is 6). It also rate limits the requests to prevent `Loader` from trashing
/// underlying systems (e.g. `URLSession`). The rate limiter only comes into play
/// when the requests are started and cancelled at a high rate (e.g. fast
/// scrolling through a collection view).
///
/// `Loader` features can be configured using `Loader.Options`.
///
/// `Loader` is thread-safe.
public final class Loader: Loading {
    private let loader: DataLoading
    private let decoder: DataDecoding
    private var tasks = [AnyHashable: Task]()

    // Synchronization queue
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Loader")

    // Queues limiting underlying systems
    private let dataLoadingQueue = OperationQueue()
    private let decodingQueue = DispatchQueue(label: "com.github.kean.Nuke.Decoding")
    private let processingQueue = OperationQueue()
    private let rateLimiter = RateLimiter()
    private let options: Options

    /// Shared `Loading` object.
    ///
    /// Shared loader is created with `DataLoader()`.
    public static let shared: Loading = Loader(loader: DataLoader())

    /// Some nitty-gritty options which can be used to customize loader.
    public struct Options {
        /// The maximum number of concurrent data loading tasks. `6` by default.
        public var maxConcurrentDataLoadingTaskCount: Int = 6

        /// The maximum number of concurrent image processing tasks. `2` by default.
        ///
        /// Parallelizing image processing might result in a performance boost
        /// in a certain scenarios, however it's not going to be noticable in most
        /// cases. Might increase memory usage.
        public var maxConcurrentImageProcessingTaskCount: Int = 2

        /// `true` by default. If `true` loader combines the requests with the
        /// same `loadKey` into a single request. The request only gets cancelled
        /// when all the registered requests are.
        public var isDeduplicationEnabled = true

        /// `true` by default. It `true` loader rate limits the requests to
        /// prevent `Loader` from trashing underlying systems (e.g. `URLSession`).
        /// The rate limiter only comes into play when the requests are started
        /// and cancelled at a high rate (e.g. scrolling through a collection view).
        public var isRateLimiterEnabled = true

        /// Returns a processor for the given image and request. By default
        /// returns `request.processor`. Please keep in mind that you can
        /// override the processor from the request using this option but you're
        /// not going to override the processor used as a cache key.
        public var processor: (Image, Request) -> AnyProcessor? = { $1.processor }

        /// Creates default options.
        public init() {}
    }

    /// Initializes `Loader` instance with the given loader, decoder.
    /// - parameter decoder: `DataDecoder()` by default.
    /// - parameter options: Options which can be used to customize loader.
    public init(loader: DataLoading, decoder: DataDecoding = DataDecoder(), options: Options = Options()) {
        self.loader = loader
        self.decoder = decoder
        self.dataLoadingQueue.maxConcurrentOperationCount = options.maxConcurrentDataLoadingTaskCount
        self.processingQueue.maxConcurrentOperationCount = options.maxConcurrentImageProcessingTaskCount
        self.options = options
    }

    // MARK: Loading

    /// Loads an image for the given request using image loading pipeline.
    public func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        queue.async {
            if token?.isCancelling == true { return } // Fast preflight check
            self._loadImage(request, token: token, completion: completion)
        }
    }

    private func _loadImage(_ request: Request, token: CancellationToken?, completion: @escaping Completion) {
        let task = _startTask(with: request)

        // Register handler with a task.
        let handler = Task.Handler(request: request, completion: completion)
        task.handlers.insert(handler)

        // Update data operation priority (in case it was already started).
        task.dataOperation?.queuePriority = _priority(for: task.handlers).queuePriority

        token?.register { [weak self, weak task, weak handler] in
            guard let task = task, let handler = handler else { return }
            self?._cancel(task, handler: handler)
        }
    }

    // MARK: Managing Tasks

    private func _startTask(with request: Request) -> Task {
        // Check if task for the given key already exists.
        //
        // This part is more clever than I would like. The reason why we need a
        // key even when deduplication is disabled is to have a way to retain
        // a task by storing it in `tasks` dictionary.
        let key = options.isDeduplicationEnabled ? request.loadKey : UUID()
        if let task = tasks[key] {
            return task
        }
        let task = Task(request: request, key: key)
        tasks[key] = task
        _loadImage(for: task) // Start the pipeline
        return task
    }

    // Report progress to all registered handlers.
    private func _updateProgress(completed: Int64, total: Int64, task: Task) {
        queue.async {
            #if swift(>=4.1)
            let handlers = task.handlers.compactMap { $0.request.progress }
            #else
            let handlers = task.handlers.flatMap { $0.request.progress }
            #endif
            guard !handlers.isEmpty else { return }
            DispatchQueue.main.async { handlers.forEach { $0(completed, total) } }
        }
    }

    // Report completion to all registered handlers.
    private func _complete(_ task: Task, result: Result<Image>) {
        queue.async {
            let handlers = task.handlers // Always non-empty at this point, no need to check
            DispatchQueue.main.async { handlers.forEach { $0.completion(result) } }
            if self.tasks[task.key] === task {
                self.tasks[task.key] = nil
            }
        }
    }

    // Cancel the task in case all handlers were removed.
    private func _cancel(_ task: Task, handler: Task.Handler) {
        queue.async {
            task.handlers.remove(handler)
            // Cancel the task when there are no handlers remaining.
            if task.handlers.isEmpty {
                task.cts.cancel()
                if self.tasks[task.key] === task {
                    self.tasks[task.key] = nil
                }
            }
        }
    }

    // MARK: Pipeline
    //
    // This is where the images actually get loaded.

    private func _loadImage(for task: Task) {
        // Use rate limiter to prevent trashing of the underlying systems
        if options.isRateLimiterEnabled {
            rateLimiter.execute(token: task.cts.token) { [weak self, weak task] in
                guard let task = task else { return }
                self?._loadData(for: task)
            }
        } else { // Start loading immediately.
            _loadData(for: task)
        }
    }

    private func _loadData(for task: Task) {
        let token = task.cts.token
        let request = task.request.urlRequest

        guard !token.isCancelling else { return } // Preflight check

        // Wrap data request in an operation to limit maximum number of
        // concurrent data tasks.
        let operation = Operation(starter: { [weak self, weak task] finish in
            self?.loader.loadData(
                with: request,
                token: token,
                progress: {
                    guard let task = task else { return }
                    self?._updateProgress(completed: $0, total: $1, task: task)
                },
                completion: {
                    finish()
                    guard let task = task else { return }
                    self?._didReceiveData($0, task: task)
                }
            )
            token.register(finish) // Make sure we always finish the operation.
        })

        // Synchronize access to `task.handlers`.
        queue.async {
            operation.queuePriority = _priority(for: task.handlers).queuePriority
            self.dataLoadingQueue.addOperation(operation)
            token.register { [weak operation] in operation?.cancel() }
            task.dataOperation = operation
        }
    }

    private func _didReceiveData(_ result: Result<(Data, URLResponse)>, task: Task) {
        switch result {
        case let .success(val): _decode(response: val, task: task)
        case let .failure(err): _complete(task, result: .failure(err))
        }
    }

    private func _decode(response: (Data, URLResponse), task: Task) {
        let decode = { [decoder = self.decoder] in
            decoder.decode(data: response.0, response: response.1)
        }
        decodingQueue.async { [weak self, weak task] in
            guard let task = task else { return }
            guard let image = autoreleasepool(invoking: decode) else {
                self?._complete(task, result: .failure(Error.decodingFailed))
                return
            }
            self?._process(image: image, task: task)
        }
    }

    private func _process(image: Image, task: Task) {
        // Check if processing is required, complete immediatelly if not.
        guard let processor = options.processor(image, task.request) else {
            _complete(task, result: .success(image))
            return
        }
        let operation = BlockOperation { [weak self, weak task] in
            guard let task = task else { return }
            let image = autoreleasepool { processor.process(image) }
            let result = image.map(Result.success) ?? .failure(Error.processingFailed)
            self?._complete(task, result: result)
        }
        task.cts.token.register { [weak operation] in operation?.cancel() }
        processingQueue.addOperation(operation)
    }

    // MARK: Task

    fileprivate final class Task {
        /// The original request with which the task was created.
        let request: Request
        let key: AnyHashable
        let cts = CancellationTokenSource()
        var handlers = Set<Handler>()
        weak var dataOperation: Operation?

        init(request: Request, key: AnyHashable) {
            self.request = request; self.key = key
        }

        final class Handler: Hashable {
            let request: Request
            let completion: Completion

            init(request: Request, completion: @escaping Completion) {
                self.request = request; self.completion = completion
            }

            static func ==(lhs: Handler, rhs: Handler) -> Bool {
                return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
            }

            var hashValue: Int {
                return ObjectIdentifier(self).hashValue
            }
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

private func _priority(for handlers: Set<Loader.Task.Handler>) -> Request.Priority {
    return handlers.map { $0.request.priority }.max() ?? .normal
}
