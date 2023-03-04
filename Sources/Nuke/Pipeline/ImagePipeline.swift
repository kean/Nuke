// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

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

    private let tasksLoadData: TaskPool<ImageLoadKey, (Data, URLResponse?), Error>
    private let tasksLoadImage: TaskPool<ImageLoadKey, ImageResponse, Error>
    private let tasksFetchDecodedImage: TaskPool<DecodedImageLoadKey, ImageResponse, Error>
    private let tasksFetchOriginalImageData: TaskPool<DataLoadKey, (Data, URLResponse?), Error>
    private let tasksProcessImage: TaskPool<ImageProcessingKey, ImageResponse, Swift.Error>

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
        self.tasksFetchDecodedImage = TaskPool(isCoalescingEnabled)
        self.tasksFetchOriginalImageData = TaskPool(isCoalescingEnabled)
        self.tasksProcessImage = TaskPool(isCoalescingEnabled)

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
        delegate.imageTaskCreated(imageTask, pipeline: self)
        let context = AsyncTaskContext()
        let task = Task<ImageResponse, Swift.Error> {
            try await self.image(for: imageTask, context: context)
        }
        let progress = AsyncStream<ImageTask.Progress> { context.progress = $0 }
        let previews = AsyncStream<ImageResponse> { context.previews = $0 }
        return AsyncImageTask(imageTask: imageTask, task: task, progress: progress, previews: previews)
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
        delegate.imageTaskCreated(task, pipeline: self)
        return try await image(for: task).image
    }

    private func image(for task: ImageTask, context: AsyncTaskContext? = nil) async throws -> ImageResponse {
        try await withTaskCancellationHandler(operation: {
            try await withUnsafeThrowingContinuation { continuation in
                self.queue.async {
                    guard task.state != .cancelled else {
                        return continuation.resume(throwing: CancellationError())
                    }
                    task.onCancel = {
                        context?.progress?.finish()
                        context?.previews?.finish()
                        continuation.resume(throwing: CancellationError())
                    }
                    self.startImageTask(task, progress: { response, progress in
                        if let response = response {
                            context?.previews?.yield(response)
                        } else {
                            context?.progress?.yield(progress)
                        }
                    }, completion: { result in
                        context?.progress?.finish()
                        context?.previews?.finish()
                        continuation.resume(with: result)
                    })
                }
            }
        }, onCancel: {
            task.cancel()
        })
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
                    guard task.state != .cancelled else {
                        return continuation.resume(throwing: CancellationError())
                    }
                    task.onCancel = {
                        continuation.resume(throwing: CancellationError())
                    }
                    self.startDataTask(task, progress: nil) { result in
                        continuation.resume(with: result.map { $0 })
                    }
                }
            }
        }, onCancel: {
            task.cancel()
        })
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
        delegate.imageTaskCreated(task, pipeline: self)
        @Sendable func start() {
            startImageTask(task, progress: progress, completion: completion)
        }
        if isConfined {
            start()
        } else {
            self.queue.async { start() }
        }
        return task
    }

    private func startImageTask(
        _ task: ImageTask,
        progress progressHandler: ((ImageResponse?, ImageTask.Progress) -> Void)?,
        completion: @escaping (Result<ImageResponse, Error>) -> Void
    ) {
        guard !isInvalidated else {
            dispatchCallback(to: task.callbackQueue) {
                let error = Error.pipelineInvalidated
                self.delegate.imageTask(task, didCompleteWithResult: .failure(error), pipeline: self)
                completion(.failure(error))
            }
            return
        }

        delegate.imageTaskDidStart(task, pipeline: self)

        tasks[task] = makeTaskLoadImage(for: task.request)
            .subscribe(priority: task.priority.taskPriority, subscriber: task) { [weak self, weak task] event in
                guard let self = self, let task = task else { return }

                if event.isCompleted {
                    self.tasks[task] = nil
                }

                self.dispatchCallback(to: task.callbackQueue) {
                    guard task.state != .cancelled else { return }
                    if event.isCompleted {
                        task.didComplete() // Important: called on callback queue and in this order
                    }
                    switch event {
                    case let .value(response, isCompleted):
                        if isCompleted {
                            self.delegate.imageTask(task, didCompleteWithResult: .success(response), pipeline: self)
                            completion(.success(response))
                        } else {
                            self.delegate.imageTask(task, didReceivePreview: response, pipeline: self)
                            progressHandler?(response, task.progress)
                        }
                    case let .progress(progress):
                        self.delegate.imageTask(task, didUpdateProgress: progress, pipeline: self)
                        task.progress = progress
                        progressHandler?(nil, progress)
                    case let .error(error):
                        self.delegate.imageTask(task, didCompleteWithResult: .failure(error), pipeline: self)
                        completion(.failure(error))
                    }
                }
        }
    }

    private func makeImageTask(request: ImageRequest, queue: DispatchQueue?, isDataTask: Bool = false) -> ImageTask {
        let task = ImageTask(taskId: nextTaskId, request: request)
        task.pipeline = self
        task.callbackQueue = queue
        task.isDataTask = isDataTask
        return task
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
        guard !isInvalidated else {
            dispatchCallback(to: task.callbackQueue) {
                let error = Error.pipelineInvalidated
                self.delegate.imageTask(task, didCompleteWithResult: .failure(error), pipeline: self)
                completion(.failure(error))
            }
            return
        }

        tasks[task] = makeTaskLoadData(for: task.request)
            .subscribe(priority: task.priority.taskPriority, subscriber: task) { [weak self, weak task] event in
                guard let self = self, let task = task else { return }

                if event.isCompleted {
                    self.tasks[task] = nil
                }

                self.dispatchCallback(to: task.callbackQueue) {
                    guard task.state != .cancelled else { return }
                    if event.isCompleted {
                        task.didComplete() // Important: called on callback queue and in this order
                    }
                    switch event {
                    case let .value(response, isCompleted):
                        if isCompleted {
                            completion(.success(response))
                        }
                    case let .progress(progress):
                        task.progress = progress
                        progressHandler?(progress.completed, progress.total)
                    case let .error(error):
                        completion(.failure(error))
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
        dispatchCallback(to: task.callbackQueue) {
            if !task.isDataTask {
                self.delegate.imageTaskDidCancel(task, pipeline: self)
            }
            task.onCancel?() // Order is important
        }
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

    // MARK: - Task Factory (Private)

    // When you request an image or image data, the pipeline creates a graph of tasks
    // (some tasks are added to the graph on demand).
    //
    // `loadImage()` call is represented by TaskLoadImage:
    //
    // TaskLoadImage -> TaskFetchDecodedImage -> TaskFetchOriginalImageData
    //               -> TaskProcessImage
    //
    // `loadData()` call is represented by TaskLoadData:
    //
    // TaskLoadData -> TaskFetchOriginalImageData
    //
    //
    // Each task represents a resource or a piece of work required to produce the
    // final result. The pipeline reduces the amount of duplicated work by coalescing
    // the tasks that represent the same work. For example, if you all `loadImage()`
    // and `loadData()` with the same request, only on `TaskFetchOriginalImageData`
    // is created. The work is split between tasks to minimize any duplicated work.

    func makeTaskLoadImage(for request: ImageRequest) -> AsyncTask<ImageResponse, Error>.Publisher {
        tasksLoadImage.publisherForKey(request.makeImageLoadKey()) {
            TaskLoadImage(self, request)
        }
    }

    func makeTaskLoadData(for request: ImageRequest) -> AsyncTask<(Data, URLResponse?), Error>.Publisher {
        tasksLoadData.publisherForKey(request.makeImageLoadKey()) {
            TaskLoadData(self, request)
        }
    }

    func makeTaskProcessImage(key: ImageProcessingKey, process: @escaping () throws -> ImageResponse) -> AsyncTask<ImageResponse, Swift.Error>.Publisher {
        tasksProcessImage.publisherForKey(key) {
            OperationTask(self, configuration.imageProcessingQueue, process)
        }
    }

    func makeTaskFetchDecodedImage(for request: ImageRequest) -> AsyncTask<ImageResponse, Error>.Publisher {
        tasksFetchDecodedImage.publisherForKey(request.makeDecodedImageLoadKey()) {
            TaskFetchDecodedImage(self, request)
        }
    }

    func makeTaskFetchOriginalImageData(for request: ImageRequest) -> AsyncTask<(Data, URLResponse?), Error>.Publisher {
        tasksFetchOriginalImageData.publisherForKey(request.makeDataLoadKey()) {
            request.publisher == nil ?
                TaskFetchOriginalImageData(self, request) :
                TaskFetchWithPublisher(self, request)
        }
    }
}
