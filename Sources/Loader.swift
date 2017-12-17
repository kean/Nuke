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
/// object, and transform the image using processors (`Processing`) provided
/// in the `Request`.
///
/// `Loader` combines the requests with the same `loadKey` into a single request.
/// The request only gets cancelled when all the underlying requests are.
///
/// `Loader` limits the number of concurrent requests (the default maximum limit
/// is 6). It also rate limits the requests to prevent `Loader` from trashing
/// underlying systems with the requests (e.g. `URLSession`). The rate limiter
/// only comes into play when the requests are started and cancelled at a high
/// rate (e.g. fast scrolling through a collection view).
///
/// `Loader` is thread-safe.
public final class Loader: Loading {
    private let loader: DataLoading
    private let decoder: DataDecoding
    private var tasks = [AnyHashable: Task]()

    // synchronization queue
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Loader")

    // queues limiting underlying systems
    private let taskQueue: TaskQueue
    private let decodingQueue = DispatchQueue(label: "com.github.kean.Nuke.Decoding")
    private let processingQueue = DispatchQueue(label: "com.github.kean.Nuke.Processing")
    private let rateLimiter = RateLimiter()

    /// Returns a processor for the given image and request. Default
    /// implementation simply returns `request.processor`.
    public var makeProcessor: (Image, Request) -> AnyProcessor? = {
        return $1.processor
    }

    /// Shared `Loading` object.
    ///
    /// Shared loader is created with `DataLoader()`.
    public static let shared: Loading = Loader(loader: DataLoader())

    /// Initializes `Loader` instance with the given loader, decoder.
    /// - parameter decoder: `DataDecoder()` by default.
    /// - parameter `maxConcurrentRequestCount`: 6 by default.
    public init(loader: DataLoading, decoder: DataDecoding = DataDecoder(), maxConcurrentRequestCount: Int = 6) {
        self.loader = loader
        self.decoder = decoder
        self.taskQueue = TaskQueue(maxConcurrentTaskCount: maxConcurrentRequestCount)
    }

    // MARK: Loading

    /// Loads an image for the given request using image loading pipeline.
    public func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        queue.async {
            if token?.isCancelling == true { return } // Fast preflight check
            self._loadImageDeduplicating(request, token: token, completion: completion)
        }
    }

    // MARK: Deduplication

    private func _loadImageDeduplicating(_ request: Request, token: CancellationToken?, completion: @escaping Completion) {
        let task = _startTask(with: request)

        // Combine requests with the same `loadKey` into a single request.
        // The request only gets cancelled when all the underlying requests are.
        task.retainCount += 1
        let handler = Task.Handler(progress: request.progress, completion: completion)
        task.handlers.append(handler)

        token?.register { [weak self, weak task] in
            if let task = task { self?._cancel(task) }
        }
    }

    private func _startTask(with request: Request) -> Task {
        // Check if the task for the same request already exists.
        let key = Request.loadKey(for: request)
        guard let task = tasks[key] else {
            let task = Task(request: request, key: key)
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

    private func _progress(completed: Int64, total: Int64, task: Task) {
        queue.async {
            let handlers = task.handlers.flatMap { $0.progress }
            guard !handlers.isEmpty else { return }
            DispatchQueue.main.async { handlers.forEach { $0(completed, total) } }
        }
    }

    private func _complete(_ task: Task, result: Result<Image>) {
        queue.async {
            guard self.tasks[task.key] === task else { return } // check if still registered
            let handlers = task.handlers
            DispatchQueue.main.async { handlers.forEach { $0.completion(result) } }
            self.tasks[task.key] = nil
        }
    }

    private func _cancel(_ task: Task) {
        queue.async {
            guard self.tasks[task.key] === task else { return } // check if still registered
            task.retainCount -= 1 // CTS makes sure cancel can't be called twice
            if task.retainCount == 0 {
                task.cts.cancel() // cancel underlying request
                self.tasks[task.key] = nil
            }
        }
    }

    private final class Task {
        let request: Request
        let key: AnyHashable

        let cts = CancellationTokenSource()
        var handlers = [Handler]()
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
        rateLimiter.execute(token: token) { [weak self] in
            self?._loadData(with: request, token: token, completion: completion)
        }
    }

    // would be nice to rewrite to async/await
    private func _loadData(with request: Request, token: CancellationToken, completion: @escaping Completion) {
        taskQueue.execute(token: token) { [weak self] finish in
            self?.loader.loadData(with: request.urlRequest, token: token, progress: {
                request.progress?($0, $1)
            }, completion: {
                finish()

                switch $0 {
                case let .success(val): self?._decode(response: val, request: request, token: token, completion: completion)
                case let .failure(err): completion(.failure(err))
                }
            })
            token.register { finish() }
        }
    }

    private func _decode(response: (Data, URLResponse), request: Request, token: CancellationToken, completion: @escaping Completion) {
        decodingQueue.execute(token: token) { [weak self] in
            guard let image = self?.decoder.decode(data: response.0, response: response.1) else {
                completion(.failure(Error.decodingFailed)); return
            }
            self?._process(image: image, request: request, token: token, completion: completion)
        }
    }

    private func _process(image: Image, request: Request, token: CancellationToken, completion: @escaping Completion) {
        guard let processor = makeProcessor(image, request) else {
            completion(.success(image)); return // no need to process
        }
        processingQueue.execute(token: token) {
            guard let image = processor.process(image) else {
                completion(.failure(Error.processingFailed)); return
            }
            completion(.success(image))
        }
    }

    // MARK: Misc

    /// Error returns by `Loader` class itself. `Loader` might also return
    /// errors from underlying `DataLoading` object.
    public enum Error: Swift.Error {
        case decodingFailed
        case processingFailed
    }
}
