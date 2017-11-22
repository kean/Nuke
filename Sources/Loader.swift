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

/// `Loader` implements an image loading pipeline:
///
/// 1. Load data using an object conforming to `DataLoading` protocol.
/// 2. Create an image with the data using `DataDecoding` object.
/// 3. Transform the image using processor (`Processing`) provided in the request.
///
/// `Loader` is thread-safe.
public final class Loader: Loading {
    private let loader: DataLoading
    private let decoder: DataDecoding
    private let schedulers: Schedulers
    private var tasks = [AnyHashable: Task]()
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Loader")

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
    /// - parameter schedulers: `Schedulers()` by default.
    public init(loader: DataLoading, decoder: DataDecoding = DataDecoder(), schedulers: Schedulers = Schedulers()) {
        self.loader = loader
        self.decoder = decoder
        self.schedulers = schedulers
    }

    /// Loads an image for the given request using image loading pipeline.
    public func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        queue.async {
            if token?.isCancelling == true { return } // Fast preflight check
            self._loadImage(with: request, token: token, completion: completion)
        }
    }

    private func _loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        let task = _startTask(with: request)

        // Combine requests with the same `loadKey` into a single request.
        // The request only gets cancelled when all the underlying requests are.
        task.retainCount += 1
        task.handlers.append(completion)

        token?.register { [weak self, weak task] in
            if let task = task { self?._cancel(task) }
        }
    }

    // Returns existing task (if there is one). Returns a new task otherwise.
    private func _startTask(with request: Request) -> Task {
        let key = Request.loadKey(for: request)
        if let task = tasks[key] { return task } // already running
        let task = Task(request: request, key: key)
        tasks[key] = task
        _loadImage(with: task)
        return task
    }

    private func _loadImage(with task: Task) { // would be nice to rewrite to async/await
        self.loader.loadData(with: task.request, token: task.cts.token) { [weak self] in
            switch $0 {
            case let .success(val): self?.decode(response: val, task: task)
            case let .failure(err): self?._complete(task, result: .failure(err))
            }
        }
    }

    private func decode(response: (Data, URLResponse), task: Task) {
        queue.async {
            self.schedulers.decoding.execute(token: task.cts.token) { [weak self] in
                if let image = self?.decoder.decode(data: response.0, response: response.1) {
                    self?.process(image: image, task: task)
                } else {
                    self?._complete(task, result: .failure(Error.decodingFailed))
                }
            }
        }
    }

    private func process(image: Image, task: Task) {
        queue.async {
            guard let processor = self.makeProcessor(image, task.request) else {
                self._complete(task, result: .success(image)) // no need to process
                return
            }
            self.schedulers.processing.execute(token: task.cts.token) { [weak self] in
                if let image = processor.process(image) {
                    self?._complete(task, result: .success(image))
                } else {
                    self?._complete(task, result: .failure(Error.processingFailed))
                }
            }
        }
    }

    private func _complete(_ task: Task, result: Result<Image>) {
        queue.async {
            guard self.tasks[task.key] === task else { return } // check if still registered
            task.handlers.forEach { $0(result) }
            self.tasks[task.key] = nil
        }
    }

    private func _cancel(_ task: Task) {
        queue.async {
            guard self.tasks[task.key] === task else { return } // check if still registered
            task.retainCount -= 1
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
        var handlers = [(Result<Image>) -> Void]()
        var retainCount = 0 // number of non-cancelled handlers

        init(request: Request, key: AnyHashable) {
            self.request = request
            self.key = key
        }
    }

    // MARK: Schedulers

    /// Schedulers used to execute a corresponding steps of the pipeline.
    public struct Schedulers {
        /// `DispatchQueueScheduler` with a serial queue by default.
        public var decoding: Scheduler = DispatchQueueScheduler(queue: DispatchQueue(label: "com.github.kean.Nuke.Decoding"))
        // There is no reason to increase `maxConcurrentOperationCount` for
        // built-in `DataDecoder` that locks globally while decoding.

        /// `DispatchQueueScheduler` with a serial queue by default.
        public var processing: Scheduler = DispatchQueueScheduler(queue: DispatchQueue(label: "com.github.kean.Nuke.Processing"))

        /// Creates a default `Schedulers`. instance.
        public init() {}
    }

    /// Error returns by `Loader` class itself. `Loader` might also return
    /// errors from underlying `DataLoading` object.
    public enum Error: Swift.Error {
        case decodingFailed
        case processingFailed
    }
}
