// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Loads images.
public protocol Loading {
    /// Loads an image with the given request.
    ///
    /// Loader doesn't make guarantees on which thread the completion
    /// closure is called and whether it gets called or not after
    /// the operation gets cancelled.
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
/// The request only gets cancelled when all the registered requests are.
///
/// `Loader` limits the number of concurrent requests (the default maximum limit
/// is 6). It also rate limits the requests to prevent `Loader` from trashing
/// underlying systems (e.g. `URLSession`). The rate limiter only comes into play
/// when the requests are started and cancelled at a high rate (e.g. fast
/// scrolling through a collection view).
///
/// Most of the `Loader` features can be configured using `Loader.Options`.
///
/// `Loader` is thread-safe.
public final class Loader: Loading {
    private let loader: DataLoading
    private let decoder: DataDecoding
    private var tasks = [AnyHashable: DeduplicatedTask]()

    // synchronization queue
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Loader")

    // queues limiting underlying systems
    private let dataLoadingQueue: TaskQueue
    private let decodingQueue = DispatchQueue(label: "com.github.kean.Nuke.Decoding")
    private let processingQueue: TaskQueue
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
        self.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: options.maxConcurrentDataLoadingTaskCount)
        self.processingQueue = TaskQueue(maxConcurrentTaskCount: options.maxConcurrentImageProcessingTaskCount)
        self.options = options
    }

    // MARK: Loading

    /// Loads an image for the given request using image loading pipeline.
    public func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        queue.async {
            if token?.isCancelling == true { return } // Fast preflight check
            if self.options.isDeduplicationEnabled {
                self._loadImageDeduplicating(request, token: token, completion: completion)
            } else {
                self._loadImage(with: request, token: token ?? .noOp, completion: completion)
            }
        }
    }

    // MARK: Deduplication

    private func _loadImageDeduplicating(_ request: Request, token: CancellationToken?, completion: @escaping Completion) {
        let task = _startTask(with: request)

        // Combine requests with the same `loadKey` into a single request.
        // The request only gets cancelled when all the underlying requests are.
        task.retainCount += 1
        let handler = DeduplicatedTask.Handler(progress: request.progress, completion: completion)
        task.handlers.append(handler)

        token?.register { [weak self, weak task] in
            if let task = task { self?._cancel(task) }
        }
    }

    private func _startTask(with request: Request) -> DeduplicatedTask {
        // Check if the task for the same request already exists.
        let key = request.loadKey
        guard let task = tasks[key] else {
            let task = DeduplicatedTask(request: request, key: key)
            tasks[key] = task

            // Start the pipeline
            var request = request // make a copy to set a custom progress handler
            request.progress = { [weak self, weak task] in
                if let task = task { self?._progress(completed: $0, total: $1, task: task) }
            }
            _loadImage(with: request, token: task.cts.token) { [weak self, weak task] in
                if let task = task { self?._complete(task, result: $0) }
            }
            return task
        }
        return task
    }

    private func _progress(completed: Int64, total: Int64, task: DeduplicatedTask) {
        queue.async {
            let handlers = task.handlers.flatMap { $0.progress }
            guard !handlers.isEmpty else { return }
            DispatchQueue.main.async { handlers.forEach { $0(completed, total) } }
        }
    }

    private func _complete(_ task: DeduplicatedTask, result: Result<Image>) {
        queue.async {
            guard self.tasks[task.key] === task else { return } // still registered
            let handlers = task.handlers // always non-empty at this point, no need to check
            DispatchQueue.main.async { handlers.forEach { $0.completion(result) } }
            self.tasks[task.key] = nil
        }
    }

    private func _cancel(_ task: DeduplicatedTask) {
        queue.async {
            guard self.tasks[task.key] === task else { return } // still registered
            task.retainCount -= 1 // CTS makes sure cancel can't be called twice
            if task.retainCount == 0 {
                task.cts.cancel() // cancel underlying request
                self.tasks[task.key] = nil
            }
        }
    }

    private final class DeduplicatedTask {
        let request: Request
        let key: AnyHashable

        // Default `Loader` + `DataLoader` combination takes full advantage of
        // CTS optimizations by only registering twice.
        let cts = CancellationTokenSource()

        var handlers = ContiguousArray<Handler>()
        var retainCount = 0 // number of non-cancelled handlers

        init(request: Request, key: AnyHashable) {
            self.request = request; self.key = key
        }

        struct Handler {
            let progress: ProgressHandler?
            let completion: (Result<Image>) -> Void
        }
    }

    // MARK: Pipeline

    private func _loadImage(with request: Request, token: CancellationToken, completion: @escaping Completion) {
        // Use rate limiter to prevent trashing of the underlying systems
        if options.isRateLimiterEnabled {
            rateLimiter.execute(token: token) { [weak self] in
                self?._loadData(with: request, token: token, completion: completion)
            }
        } else { // load directly
            _loadData(with: request, token: token, completion: completion)
        }
    }

    // would be nice to rewrite to async/await
    private func _loadData(with request: Request, token: CancellationToken, completion: @escaping Completion) {
        dataLoadingQueue.execute(token: token) { [weak self] finish in
            self?.loader.loadData(with: request.urlRequest, token: token, progress: {
                request.progress?($0, $1)
            }, completion: {
                finish()

                switch $0 {
                case let .success(val): self?._decode(response: val, request: request, token: token, completion: completion)
                case let .failure(err): completion(.failure(err))
                }
            })
            token.register(finish)
        }
    }

    private func _decode(response: (Data, URLResponse), request: Request, token: CancellationToken, completion: @escaping Completion) {
        let decode = { [decoder = self.decoder] in decoder.decode(data: response.0, response: response.1) }
        decodingQueue.async { [weak self] in
            guard let image = autoreleasepool(invoking: decode) else {
                completion(.failure(Error.decodingFailed)); return
            }
            self?._process(image: image, request: request, token: token, completion: completion)
        }
    }

    private func _process(image: Image, request: Request, token: CancellationToken, completion: @escaping Completion) {
        guard let processor = options.processor(image, request) else {
            completion(.success(image)); return // no need to process
        }
        processingQueue.execute(token: token) { finish in
            let image = autoreleasepool { processor.process(image) }
            completion(image.map(Result.success) ?? .failure(Error.processingFailed))
            finish()
        }
    }

    // MARK: Misc

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
