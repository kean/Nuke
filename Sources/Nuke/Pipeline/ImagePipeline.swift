// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import Combine

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// The pipeline downloads and caches images, and prepares them for display. 
public final class ImagePipeline: @unchecked Sendable {
    /// Returns the shared image pipeline.
    public static var shared: ImagePipeline {
        get { _shared }
        set { _shared = newValue }
    }

    @Atomic
    private static var _shared = ImagePipeline(configuration: .withURLCache)

    /// The pipeline configuration.
    public let configuration: Configuration

    /// Provides access to the underlying caching subsystems.
    public var cache: ImagePipeline.Cache { ImagePipeline.Cache(pipeline: self) }

    let delegate: any ImagePipelineDelegate

    private var tasks = [ImageTask: TaskSubscription]()

    private let tasksLoadData: TaskPool<TaskLoadImageKey, ImageResponse, Error>
    private let tasksLoadImage: TaskPool<TaskLoadImageKey, ImageResponse, Error>
    private let tasksFetchOriginalImage: TaskPool<TaskFetchOriginalImageKey, ImageResponse, Error>
    private let tasksFetchOriginalData: TaskPool<TaskFetchOriginalDataKey, (Data, URLResponse?), Error>

    // The queue on which the entire subsystem is synchronized.
    let queue = DispatchQueue(label: "com.github.kean.Nuke.ImagePipeline", qos: .userInitiated)
    private var isInvalidated = false

    private var nextTaskId: Int64 {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        _nextTaskId += 1
        return _nextTaskId
    }
    private var _nextTaskId: Int64 = 0
    private let lock: os_unfair_lock_t

    let rateLimiter: RateLimiter?
    let id = UUID()

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()

        ResumableDataStorage.shared.unregister(self)
    }

    /// Initializes the instance with the given configuration.
    ///
    /// - parameters:
    ///   - configuration: The pipeline configuration.
    ///   - delegate: Provides more ways to customize the pipeline behavior on per-request basis.
    public init(configuration: Configuration = Configuration(), delegate: (any ImagePipelineDelegate)? = nil) {
        self.configuration = configuration
        self.rateLimiter = configuration.isRateLimiterEnabled ? RateLimiter(queue: queue) : nil
        self.delegate = delegate ?? ImagePipelineDefaultDelegate()
        (configuration.dataLoader as? DataLoader)?.prefersIncrementalDelivery = configuration.isProgressiveDecodingEnabled

        let isCoalescingEnabled = configuration.isTaskCoalescingEnabled
        self.tasksLoadData = TaskPool(isCoalescingEnabled)
        self.tasksLoadImage = TaskPool(isCoalescingEnabled)
        self.tasksFetchOriginalImage = TaskPool(isCoalescingEnabled)
        self.tasksFetchOriginalData = TaskPool(isCoalescingEnabled)

        self.lock = .allocate(capacity: 1)
        self.lock.initialize(to: os_unfair_lock())

        ResumableDataStorage.shared.register(self)
    }

    /// A convenience way to initialize the pipeline with a closure.
    ///
    /// Example usage:
    ///
    /// ```swift
    /// ImagePipeline {
    ///     $0.dataCache = try? DataCache(name: "com.myapp.datacache")
    ///     $0.dataCachePolicy = .automatic
    /// }
    /// ```
    ///
    /// - parameters:
    ///   - configuration: The pipeline configuration.
    ///   - delegate: Provides more ways to customize the pipeline behavior on per-request basis.
    public convenience init(delegate: (any ImagePipelineDelegate)? = nil, _ configure: (inout ImagePipeline.Configuration) -> Void) {
        var configuration = ImagePipeline.Configuration()
        configure(&configuration)
        self.init(configuration: configuration, delegate: delegate)
    }

    /// Invalidates the pipeline and cancels all outstanding tasks. Any new
    /// requests will immediately fail with ``ImagePipeline/Error/pipelineInvalidated`` error.
    public func invalidate() {
        queue.async {
            guard !self.isInvalidated else { return }
            self.isInvalidated = true
            self.tasks.keys.forEach { self.cancel($0) }
        }
    }

    // MARK: - Loading Images (Async/Await)

    /// Creates a task with the given URL.
    public func imageTask(with url: URL) -> AsyncImageTask {
        imageTask(with: ImageRequest(url: url))
    }

    /// Creates a task with the given request.
    public func imageTask(with request: ImageRequest) -> AsyncImageTask {
        let imageTask = makeImageTask(request: request, queue: queue)
        let context = AsyncTaskContext()
        let task = Task<ImageResponse, Swift.Error> {
            try await self.image(for: imageTask, context: context)
        }
        let events = AsyncStream<ImageTask.Event> { context.events = $0 }
        return AsyncImageTask(imageTask: imageTask, task: task, events: events)
    }

    /// Returns an image for the given URL.
    ///
    /// - parameters:
    ///   - request: An image URL.
    public func image(for url: URL) async throws -> PlatformImage {
        try await image(for: ImageRequest(url: url))
    }

    /// Returns an image for the given request.
    ///
    /// - parameters:
    ///   - request: An image request.
    public func image(for request: ImageRequest) async throws -> PlatformImage {
        // Optimization: fetch image directly without creating an associated task
        let task = makeImageTask(request: request, queue: queue)
        return try await image(for: task).image
    }

    private func image(for task: ImageTask, context: AsyncTaskContext? = nil) async throws -> ImageResponse {
        try await withTaskCancellationHandler(operation: {
            try await withUnsafeThrowingContinuation { continuation in
                self.queue.async {
                    self.loadImage(for: task, context: context, continuation: continuation)
                }
            }
        }, onCancel: {
            task.cancel()
        })
    }

    private func loadImage(for task: ImageTask, context: AsyncTaskContext?, continuation: UnsafeContinuation<ImageResponse, any Swift.Error>) {
        startImageTask(task) { event, _, _ in
            context?.events?.yield(event)
            switch event {
            case .cancelled:
                context?.events?.finish()
                continuation.resume(throwing: CancellationError())
            case .finished(let result):
                context?.events?.finish()
                continuation.resume(with: result)
            default:
                break
            }
        }
    }

    // MARK: - Loading Data (Async/Await)

    /// Returns image data for the given URL.
    ///
    /// - parameter request: An image request.
    @discardableResult
    public func data(for url: URL) async throws -> (Data, URLResponse?) {
        try await data(for: ImageRequest(url: url))
    }

    /// Returns image data for the given request.
    ///
    /// - parameter request: An image request.
    @discardableResult
    public func data(for request: ImageRequest) async throws -> (Data, URLResponse?) {
        let task = makeImageTask(request: request, queue: nil, isDataTask: true)
        return try await withTaskCancellationHandler(operation: {
            try await withUnsafeThrowingContinuation { continuation in
                self.queue.async {
                    self.loadData(for: task, context: nil, continuation: continuation)
                }
            }
        }, onCancel: {
            task.cancel()
        })
    }

    private func loadData(for task: ImageTask, context: AsyncTaskContext?, continuation: UnsafeContinuation<(Data, URLResponse?), any Swift.Error>) {
        startImageTask(task) { event, _, _ in
            context?.events?.yield(event)
            switch event {
            case .cancelled:
                context?.events?.finish()
                continuation.resume(throwing: CancellationError())
            case .finished(let result):
                context?.events?.finish()
                let result = result.map { response in
                    // Data should never be empty
                    (response.container.data ?? Data(), response.urlResponse)
                }
                continuation.resume(with: result)
            default:
                break
            }
        }
    }

    // MARK: - Loading Images (Closures)

    /// Loads an image for the given request.
    ///
    /// - parameters:
    ///   - request: An image request.
    ///   - completion: A closure to be called on the main thread when the request
    ///   is finished.
    @discardableResult public func loadImage(
        with url: URL,
        completion: @escaping (_ result: Result<ImageResponse, Error>) -> Void
    ) -> ImageTask {
        loadImage(with: ImageRequest(url: url), queue: nil, progress: nil, completion: completion)
    }

    /// Loads an image for the given request.
    ///
    /// - parameters:
    ///   - request: An image request.
    ///   - completion: A closure to be called on the main thread when the request
    ///   is finished.
    @discardableResult public func loadImage(
        with request: ImageRequest,
        completion: @escaping (_ result: Result<ImageResponse, Error>) -> Void
    ) -> ImageTask {
        loadImage(with: request, queue: nil, progress: nil, completion: completion)
    }

    /// Loads an image for the given request.
    ///
    /// - parameters:
    ///   - request: An image request.
    ///   - queue: A queue on which to execute `progress` and `completion` callbacks.
    ///   By default, the pipeline uses `.main` queue.
    ///   - progress: A closure to be called periodically on the main thread when
    ///   the progress is updated.
    ///   - completion: A closure to be called on the main thread when the request
    ///   is finished.
    @discardableResult public func loadImage(
        with request: ImageRequest,
        queue: DispatchQueue? = nil,
        progress: ((_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)?,
        completion: @escaping (_ result: Result<ImageResponse, Error>) -> Void
    ) -> ImageTask {
        loadImage(with: request, isConfined: false, queue: queue, progress: {
            progress?($0, $1.completed, $1.total)
        }, completion: completion)
    }

    func loadImage(
        with request: ImageRequest,
        isConfined: Bool,
        queue callbackQueue: DispatchQueue?,
        progress: ((ImageResponse?, ImageTask.Progress) -> Void)?,
        completion: @escaping (Result<ImageResponse, Error>) -> Void
    ) -> ImageTask {
        let task = makeImageTask(request: request, queue: callbackQueue)
        @Sendable func start() {
            loadImage(task, progress: progress, completion: completion)
        }
        if isConfined {
            start()
        } else {
            self.queue.async { start() }
        }
        return task
    }

    private func loadImage(
        _ task: ImageTask,
        progress progressHandler: ((ImageResponse?, ImageTask.Progress) -> Void)?,
        completion: @escaping (Result<ImageResponse, Error>) -> Void
    ) {
        startImageTask(task) { event, task, pipeline in
            pipeline.dispatchCallback(to: task.callbackQueue) {
                guard task.state != .cancelled else {
                    // The callback-based API guarantees that after cancellation no
                    // event are called on the callback queue.
                    return
                }
                switch event {
                case .progress(let progress):
                    progressHandler?(nil, progress)
                case .preview(let response):
                    progressHandler?(response, task.progress)
                case .cancelled:
                    break // The legacy APIs do not send cancellation events
                case .finished(let result):
                    completion(result)
                }
            }
        }
    }

    // MARK: - ImageTask (Internal)

    private func makeImageTask(request: ImageRequest, queue: DispatchQueue?, isDataTask: Bool = false) -> ImageTask {
        let task = ImageTask(taskId: nextTaskId, request: request)
        task.pipeline = self
        task.callbackQueue = queue
        task.isDataTask = isDataTask
        delegate.imageTaskCreated(task, pipeline: self)
        return task
    }

    private func startImageTask(_ task: ImageTask, _ onEvent: @escaping (ImageTask.Event, ImageTask, ImagePipeline) -> Void) {
        assert(task.onEvent == nil)
        task.onEvent = onEvent
        guard !isInvalidated else {
            return send(.finished(.failure(.pipelineInvalidated)), task)
        }
        guard task.state != .cancelled else {
            return send(.cancelled, task)
        }
        delegate.imageTaskDidStart(task, pipeline: self)
        if !task.isDataTask {
            tasks[task] = makeTaskLoadImage(for: task.request).subscribe(priority: task.priority.taskPriority, subscriber: task) { [weak self, weak task] in
                guard let self, let task else { return }
                imageTask(task, didReceiveEvent: $0)
            }
        } else {
            tasks[task] = makeTaskLoadData(for: task.request).subscribe(priority: task.priority.taskPriority, subscriber: task) { [weak self, weak task] in
                guard let self, let task else { return }
                imageTask(task, didReceiveEvent: $0)
            }
        }
    }

    private func imageTask(_ task: ImageTask, didReceiveEvent event: AsyncTask<ImageResponse, ImagePipeline.Error>.Event) {
        if event.isCompleted {
            tasks[task] = nil
            task.didComplete()
        }
        switch event {
        case let .value(response, isCompleted):
            if isCompleted {
                send(.finished(.success(response)), task)
            } else {
                send(.preview(response), task)
            }
        case let .progress(progress):
            task.progress = progress
            send(.progress(progress), task)
        case let .error(error):
            send(.finished(.failure(error)), task)
        }
    }

    private func send(_ event: ImageTask.Event, _ task: ImageTask) {
        task.onEvent?(event, task, self)
        logEvent(event, for: task)
    }

    // MARK: - Loading Data (Closures)

    /// Loads image data for the given request. The data doesn't get decoded
    /// or processed in any other way.
    @discardableResult public func loadData(
        with url: URL,
        completion: @escaping (Result<(data: Data, response: URLResponse?), Error>) -> Void
    ) -> ImageTask {
        loadData(with: ImageRequest(url: url), queue: nil, progress: nil, completion: completion)
    }

    /// Loads image data for the given request. The data doesn't get decoded
    /// or processed in any other way.
    @discardableResult public func loadData(
        with request: ImageRequest,
        completion: @escaping (Result<(data: Data, response: URLResponse?), Error>) -> Void
    ) -> ImageTask {
        loadData(with: request, queue: nil, progress: nil, completion: completion)
    }

    /// Loads the image data for the given request. The data doesn't get decoded
    /// or processed in any other way.
    ///
    /// You can call ``loadImage(with:completion:)-43osv`` for the request at any point after calling
    /// ``loadData(with:completion:)-6cwk3``, the pipeline will use the same operation to load the data,
    /// no duplicated work will be performed.
    ///
    /// - parameters:
    ///   - request: An image request.
    ///   - queue: A queue on which to execute `progress` and `completion`
    ///   callbacks. By default, the pipeline uses `.main` queue.
    ///   - progress: A closure to be called periodically on the main thread when the progress is updated.
    ///   - completion: A closure to be called on the main thread when the request is finished.
    @discardableResult public func loadData(
        with request: ImageRequest,
        queue: DispatchQueue? = nil,
        progress: ((_ completed: Int64, _ total: Int64) -> Void)?,
        completion: @escaping (Result<(data: Data, response: URLResponse?), Error>) -> Void
    ) -> ImageTask {
        loadData(with: request, isConfined: false, queue: queue, progress: progress, completion: completion)
    }

    func loadData(
        with request: ImageRequest,
        isConfined: Bool,
        queue: DispatchQueue?,
        progress: ((_ completed: Int64, _ total: Int64) -> Void)?,
        completion: @escaping (Result<(data: Data, response: URLResponse?), Error>) -> Void
    ) -> ImageTask {
        let task = makeImageTask(request: request, queue: queue, isDataTask: true)
        @Sendable func start() {
            startDataTask(task, progress: progress, completion: completion)
        }
        if isConfined {
            start()
        } else {
            self.queue.async { start() }
        }
        return task
    }

    private func startDataTask(
        _ task: ImageTask,
        progress progressHandler: ((_ completed: Int64, _ total: Int64) -> Void)?,
        completion: @escaping (Result<(data: Data, response: URLResponse?), Error>) -> Void
    ) {
        startImageTask(task) { event, task, pipeline in
            pipeline.dispatchCallback(to: task.callbackQueue) {
                guard task.state != .cancelled else {
                    // The callback-based API guarantees that after cancellation no
                    // event are called on the callback queue.
                    return
                }
                switch event {
                case .progress(let progress):
                    progressHandler?(progress.completed, progress.total)
                case .preview:
                    break // Should not be used for data
                case .cancelled:
                    break // The legacy APIs do not send cancellation events
                case .finished(let result):
                    let result = result.map { response in
                        // Data should never be empty
                        (data: response.container.data ?? Data(), response: response.urlResponse)
                    }
                    completion(result)
                }
            }
        }
    }

    // MARK: - Loading Images (Combine)

    /// Returns a publisher which starts a new ``ImageTask`` when a subscriber is added.
    public func imagePublisher(with url: URL) -> AnyPublisher<ImageResponse, Error> {
        imagePublisher(with: ImageRequest(url: url))
    }

    /// Returns a publisher which starts a new ``ImageTask`` when a subscriber is added.
    public func imagePublisher(with request: ImageRequest) -> AnyPublisher<ImageResponse, Error> {
        ImagePublisher(request: request, pipeline: self).eraseToAnyPublisher()
    }

    // MARK: - Image Task Events

    func imageTaskCancelCalled(_ task: ImageTask) {
        queue.async {
            self.cancel(task)
        }
    }

    private func cancel(_ task: ImageTask) {
        guard let subscription = tasks.removeValue(forKey: task) else { return }
        send(.cancelled, task)
        subscription.unsubscribe()
    }

    func imageTaskUpdatePriorityCalled(_ task: ImageTask, priority: ImageRequest.Priority) {
        queue.async {
            self.tasks[task]?.setPriority(priority.taskPriority)
        }
    }

    private func dispatchCallback(to callbackQueue: DispatchQueue?, _ closure: @escaping () -> Void) {
        if callbackQueue === self.queue {
            closure()
        } else {
            (callbackQueue ?? self.configuration.callbackQueue).async(execute: closure)
        }
    }

    // MARK: - Logging

    private func logEvent(_ event: ImageTask.Event, for task: ImageTask) {
        guard !task.isDataTask else { return }
        switch event {
        case .progress(let progress):
            delegate.imageTask(task, didUpdateProgress: progress, pipeline: self)
        case .preview(let response):
            delegate.imageTask(task, didReceivePreview: response, pipeline: self)
        case .cancelled:
            delegate.imageTaskDidCancel(task, pipeline: self)
        case .finished(let result):
            delegate.imageTask(task, didCompleteWithResult: result, pipeline: self)
        }
    }

    // MARK: - Task Factory (Private)

    // When you request an image or image data, the pipeline creates a graph of tasks
    // (some tasks are added to the graph on demand).
    //
    // `loadImage()` call is represented by TaskLoadImage:
    //
    // TaskLoadImage -> TaskFetchOriginalImage -> TaskFetchOriginalData
    //
    // `loadData()` call is represented by TaskLoadData:
    //
    // TaskLoadData -> TaskFetchOriginalData
    //
    //
    // Each task represents a resource or a piece of work required to produce the
    // final result. The pipeline reduces the amount of duplicated work by coalescing
    // the tasks that represent the same work. For example, if you all `loadImage()`
    // and `loadData()` with the same request, only on `TaskFetchOriginalImageData`
    // is created. The work is split between tasks to minimize any duplicated work.

    func makeTaskLoadImage(for request: ImageRequest) -> AsyncTask<ImageResponse, Error>.Publisher {
        tasksLoadImage.publisherForKey(TaskLoadImageKey(request)) {
            TaskLoadImage(self, request)
        }
    }

    func makeTaskLoadData(for request: ImageRequest) -> AsyncTask<ImageResponse, Error>.Publisher {
        tasksLoadData.publisherForKey(TaskLoadImageKey(request)) {
            TaskLoadData(self, request)
        }
    }

    func makeTaskFetchOriginalImage(for request: ImageRequest) -> AsyncTask<ImageResponse, Error>.Publisher {
        tasksFetchOriginalImage.publisherForKey(TaskFetchOriginalImageKey(request)) {
            TaskFetchOriginalImage(self, request)
        }
    }

    func makeTaskFetchOriginalData(for request: ImageRequest) -> AsyncTask<(Data, URLResponse?), Error>.Publisher {
        tasksFetchOriginalData.publisherForKey(TaskFetchOriginalDataKey(request)) {
            request.publisher == nil ?
                TaskFetchOriginalData(self, request) :
                TaskFetchWithPublisher(self, request)
        }
    }
}
