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
        get { _shared.value }
        set { _shared.value = newValue }
    }

    private static let _shared = Atomic(value: ImagePipeline(configuration: .withURLCache))

    /// The pipeline configuration.
    public let configuration: Configuration

    /// Provides access to the underlying caching subsystems.
    public var cache: ImagePipeline.Cache { .init(pipeline: self) }

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
    var onTaskStarted: ((ImageTask) -> Void)? // Debug purposes

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
            self.tasks.keys.forEach(self.cancelImageTask)
        }
    }

    // MARK: - Loading Images (Async/Await)

    /// Creates a task with the given URL.
    ///
    /// The task starts executing the moment it is created.
    public func imageTask(with url: URL) -> ImageTask {
        imageTask(with: ImageRequest(url: url))
    }

    /// Creates a task with the given request.
    ///
    /// The task starts executing the moment it is created.
    public func imageTask(with request: ImageRequest) -> ImageTask {
        makeStartedImageTask(with: request)
    }

    /// Returns an image for the given URL.
    public func image(for url: URL) async throws -> PlatformImage {
        try await image(for: ImageRequest(url: url))
    }

    /// Returns an image for the given request.
    public func image(for request: ImageRequest) async throws -> PlatformImage {
        try await imageTask(with: request).image
    }

    // MARK: - Loading Data (Async/Await)

    /// Returns image data for the given request.
    ///
    /// - parameter request: An image request.
    public func data(for request: ImageRequest) async throws -> (Data, URLResponse?) {
        let task = makeStartedImageTask(with: request, isDataTask: true)
        let response = try await task.response
        return (response.container.data ?? Data(), response.urlResponse)
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
        _loadImage(with: ImageRequest(url: url), progress: nil, completion: completion)
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
        _loadImage(with: request, progress: nil, completion: completion)
    }

    /// Loads an image for the given request.
    ///
    /// - parameters:
    ///   - request: An image request.
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
        _loadImage(with: request, queue: queue, progress: {
            progress?($0, $1.completed, $1.total)
        }, completion: completion)
    }

    func _loadImage(
        with request: ImageRequest,
        isDataTask: Bool = false,
        queue callbackQueue: DispatchQueue? = nil,
        progress: ((ImageResponse?, ImageTask.Progress) -> Void)?,
        completion: @escaping (Result<ImageResponse, Error>) -> Void
    ) -> ImageTask {
        makeStartedImageTask(with: request, isDataTask: isDataTask) { [weak self] event, task in
            self?.dispatchCallback(to: callbackQueue) {
                // The callback-based API guarantees that after cancellation no
                // event are called on the callback queue.
                guard task.state != .cancelled else { return }
                switch event {
                case .progress(let value): progress?(nil, value)
                case .preview(let response): progress?(response, task.currentProgress)
                case .cancelled: break // The legacy APIs do not send cancellation events
                case .finished(let result):
                    _ = task._setState(.completed) // Important to do it on the callback queue
                    completion(result)
                }
            }
        }
    }

    // nuke-13: requires callbacks to be @MainActor @Sendable or deprecate this entire API
    private func dispatchCallback(to callbackQueue: DispatchQueue?, _ closure: @escaping () -> Void) {
        let box = UncheckedSendableBox(value: closure)
        if callbackQueue === self.queue {
            closure()
        } else {
            (callbackQueue ?? self.configuration._callbackQueue).async {
                box.value()
            }
        }
    }

    // MARK: - Loading Data (Closures)

    /// Loads image data for the given request. The data doesn't get decoded
    /// or processed in any other way.
    @discardableResult public func loadData(with request: ImageRequest, completion: @escaping (Result<(data: Data, response: URLResponse?), Error>) -> Void) -> ImageTask {
        _loadData(with: request, queue: nil, progress: nil, completion: completion)
    }

    private func _loadData(
        with request: ImageRequest,
        queue: DispatchQueue?,
        progress progressHandler: ((_ completed: Int64, _ total: Int64) -> Void)?,
        completion: @escaping (Result<(data: Data, response: URLResponse?), Error>) -> Void
    ) -> ImageTask {
        _loadImage(with: request, isDataTask: true, queue: queue) { _, progress in
            progressHandler?(progress.completed, progress.total)
        } completion: { result in
            let result = result.map { response in
                // Data should never be empty
                (data: response.container.data ?? Data(), response: response.urlResponse)
            }
            completion(result)
        }
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
        progress progressHandler: ((_ completed: Int64, _ total: Int64) -> Void)?,
        completion: @escaping (Result<(data: Data, response: URLResponse?), Error>) -> Void
    ) -> ImageTask {
        _loadImage(with: request, isDataTask: true, queue: queue) { _, progress in
            progressHandler?(progress.completed, progress.total)
        } completion: { result in
            let result = result.map { response in
                // Data should never be empty
                (data: response.container.data ?? Data(), response: response.urlResponse)
            }
            completion(result)
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

    // MARK: - ImageTask (Internal)

    private func makeStartedImageTask(with request: ImageRequest, isDataTask: Bool = false, onEvent: ((ImageTask.Event, ImageTask) -> Void)? = nil) -> ImageTask {
        let task = ImageTask(taskId: nextTaskId, request: request, isDataTask: isDataTask, pipeline: self, onEvent: onEvent)
        // Important to call it before `imageTaskStartCalled`
        if !isDataTask {
            delegate.imageTaskCreated(task, pipeline: self)
        }
        task._task = Task {
            try await withUnsafeThrowingContinuation { continuation in
                self.queue.async {
                    task._continuation = continuation
                    self.startImageTask(task, isDataTask: isDataTask)
                }
            }
        }
        return task
    }

    // By this time, the task has `continuation` set and is fully wired.
    private func startImageTask(_ task: ImageTask, isDataTask: Bool) {
        guard task._state != .cancelled else {
            // The task gets started asynchronously in a `Task` and cancellation
            // can happen before the pipeline reached `startImageTask`. In that
            // case, the `cancel` method do no send the task event.
            return task._dispatch(.cancelled)
        }
        guard !isInvalidated else {
            return task._process(.error(.pipelineInvalidated))
        }
        let worker = isDataTask ? makeTaskLoadData(for: task.request) : makeTaskLoadImage(for: task.request)
        tasks[task] = worker.subscribe(priority: task.priority.taskPriority, subscriber: task) { [weak task] in
            task?._process($0)
        }
        delegate.imageTaskDidStart(task, pipeline: self)
        onTaskStarted?(task)
    }

    private func cancelImageTask(_ task: ImageTask) {
        tasks.removeValue(forKey: task)?.unsubscribe()
        task._cancel()
    }

    // MARK: - Image Task Events

    func imageTaskCancelCalled(_ task: ImageTask) {
        queue.async { self.cancelImageTask(task) }
    }

    func imageTaskUpdatePriorityCalled(_ task: ImageTask, priority: ImageRequest.Priority) {
        queue.async {
            self.tasks[task]?.setPriority(priority.taskPriority)
        }
    }

    func imageTask(_ task: ImageTask, didProcessEvent event: ImageTask.Event, isDataTask: Bool) {
        switch event {
        case .cancelled, .finished:
            tasks[task] = nil
        default: break
        }

        if !isDataTask {
            delegate.imageTask(task, didReceiveEvent: event, pipeline: self)
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
            request.publisher == nil ? TaskFetchOriginalData(self, request) : TaskFetchWithPublisher(self, request)
        }
    }

    // MARK: - Deprecated

    // Deprecated in Nuke 12.7
    @available(*, deprecated, message: "Please the variant variant that accepts `ImageRequest` as a parameter")
    @discardableResult public func loadData(with url: URL, completion: @escaping (Result<(data: Data, response: URLResponse?), Error>) -> Void) -> ImageTask {
        loadData(with: ImageRequest(url: url), queue: nil, progress: nil, completion: completion)
    }

    // Deprecated in Nuke 12.7
    @available(*, deprecated, message: "Please the variant that accepts `ImageRequest` as a parameter")
    @discardableResult public func data(for url: URL) async throws -> (Data, URLResponse?) {
        try await data(for: ImageRequest(url: url))
    }
}
