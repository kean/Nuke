// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Combine

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// Downloads, decodes, processes, and caches images.
///
/// The pipeline is the central component of Nuke. It orchestrates a graph of
/// tasks - fetching data, decoding, processing, and decompressing images -
/// while automatically coalescing duplicate work, respecting priorities, and
/// managing multiple cache layers.
///
/// ```swift
/// let image = try await ImagePipeline.shared.image(for: url)
/// ```
///
/// Use ``ImagePipeline/Configuration-swift.struct`` to customize behavior, or
/// ``ImagePipeline/shared`` to use the default pipeline.
@ImagePipelineActor
public final class ImagePipeline: Sendable {
    /// Returns the shared image pipeline.
    nonisolated public static var shared: ImagePipeline {
        get { _shared.value }
        set { _shared.value = newValue }
    }

    private nonisolated static let _shared = Mutex(value: ImagePipeline(configuration: .withURLCache))

    /// The pipeline configuration.
    nonisolated public let configuration: Configuration

    /// Provides access to the underlying caching subsystems.
    nonisolated public var cache: ImagePipeline.Cache { .init(pipeline: self) }

    let delegate: any ImagePipeline.Delegate

    private var tasks = [ObjectIdentifier: ImageTask]()

    private let tasksLoadData: TaskPool<TaskLoadImageKey, ImageResponse, Error>
    private let tasksLoadImage: TaskPool<TaskLoadImageKey, ImageResponse, Error>
    private let tasksFetchOriginalImage: TaskPool<TaskFetchOriginalImageKey, ImageResponse, Error>
    private let tasksFetchOriginalData: TaskPool<TaskFetchOriginalDataKey, (Data, URLResponse?), Error>

    private var isInvalidated = false

    private nonisolated var nextTaskId: UInt64 {
        _nextTaskId.withLock { value in
            value += 1
            return value
        }
    }
    private nonisolated let _nextTaskId = Mutex<UInt64>(value: 0)

    let rateLimiter: RateLimiter?
    nonisolated let id = UUID()
    nonisolated(unsafe) var onTaskStarted: ((ImageTask) -> Void)? // Debug purposes

    nonisolated deinit {
        let id = self.id
        Task { @ImagePipelineActor in ResumableDataStorage.shared.unregister(id) }
    }

    /// Initializes the instance with the given configuration.
    ///
    /// - parameters:
    ///   - configuration: The pipeline configuration.
    ///   - delegate: Provides more ways to customize the pipeline behavior on per-request basis.
    nonisolated public init(
        configuration: Configuration = Configuration(),
        delegate: (any ImagePipeline.Delegate)? = nil
    ) {
        self.configuration = configuration
        self.rateLimiter = configuration.isRateLimiterEnabled ? RateLimiter() : nil
        self.delegate = delegate ?? ImagePipelineDefaultDelegate()
        (configuration.dataLoader as? DataLoader)?.prefersIncrementalDelivery = configuration.isProgressiveDecodingEnabled

        let isCoalescingEnabled = configuration.isTaskCoalescingEnabled
        self.tasksLoadData = TaskPool(isCoalescingEnabled)
        self.tasksLoadImage = TaskPool(isCoalescingEnabled)
        self.tasksFetchOriginalImage = TaskPool(isCoalescingEnabled)
        self.tasksFetchOriginalData = TaskPool(isCoalescingEnabled)

        let id = self.id
        Task { @ImagePipelineActor in ResumableDataStorage.shared.register(id) }
    }

    /// A convenient way to initialize the pipeline with a closure.
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
    ///   - delegate: Provides more ways to customize the pipeline behavior on per-request basis.
    ///   - configure: A closure to configure the pipeline.
    nonisolated public convenience init(delegate: (any ImagePipeline.Delegate)? = nil, _ configure: (inout ImagePipeline.Configuration) -> Void) {
        var configuration = ImagePipeline.Configuration()
        configure(&configuration)
        self.init(configuration: configuration, delegate: delegate)
    }

    /// Invalidates the pipeline and cancels all outstanding tasks. Any new
    /// requests will immediately fail with ``ImagePipeline/Error/pipelineInvalidated`` error.
    nonisolated public func invalidate() {
        Task { @ImagePipelineActor in
            guard !self.isInvalidated else { return }
            self.isInvalidated = true
            for task in self.tasks.values {
                self.imageTaskCancelCalled(task)
            }
        }
    }

    // MARK: - Loading Images (Async/Await)

    /// Creates a task with the given URL.
    ///
    /// The task starts executing the moment it is created.
    nonisolated public func imageTask(with url: URL) -> ImageTask {
        makeStartedImageTask(with: ImageRequest(url: url))
    }

    /// Creates a task with the given request.
    ///
    /// The task starts executing the moment it is created.
    nonisolated public func imageTask(with request: ImageRequest) -> ImageTask {
        makeStartedImageTask(with: request)
    }

    /// Returns an image for the given URL.
    nonisolated public func image(for url: URL) async throws(ImagePipeline.Error) -> PlatformImage {
        try await image(for: ImageRequest(url: url))
    }

    /// Returns an image for the given request.
    nonisolated public func image(for request: ImageRequest) async throws(ImagePipeline.Error) -> PlatformImage {
        try await imageTask(with: request).image
    }

    // MARK: - Loading Data (Async/Await)

    /// Returns image data for the given request.
    ///
    /// - parameter request: An image request.
    nonisolated public func data(for request: ImageRequest) async throws(ImagePipeline.Error) -> (Data, URLResponse?) {
        let task = makeStartedImageTask(with: request, isDataTask: true)
        let response = try await task.response
        return (response.container.data ?? Data(), response.urlResponse)
    }

    // MARK: - Loading Images (Combine)

    /// Returns a publisher which starts a new ``ImageTask`` when a subscriber is added.
    nonisolated public func imagePublisher(with url: URL) -> AnyPublisher<ImageResponse, ImagePipeline.Error> {
        imagePublisher(with: ImageRequest(url: url))
    }

    /// Returns a publisher which starts a new ``ImageTask`` when a subscriber is added.
    nonisolated public func imagePublisher(with request: ImageRequest) -> AnyPublisher<ImageResponse, ImagePipeline.Error> {
        ImagePublisher(request: request, pipeline: self).eraseToAnyPublisher()
    }

    // MARK: - ImageTask (Internal)

    nonisolated func makeStartedImageTask(with request: ImageRequest, isDataTask: Bool = false, onEvent: ((ImageTask.Event, ImageTask) -> Void)? = nil) -> ImageTask {
        let task = ImageTask(taskId: nextTaskId, request: request, isDataTask: isDataTask, pipeline: self, onEvent: onEvent)
        // Important to call it before `imageTaskStartCalled`
        if !isDataTask {
            delegate.imageTaskCreated(task, pipeline: self)
        }
        task._task = Task { @ImagePipelineActor in
            try await withUnsafeThrowingContinuation { continuation in
                task._continuation = continuation
                self.startImageTask(task, isDataTask: isDataTask)
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
            return task._dispatch(.finished(.failure(.cancelled)))
        }
        guard !isInvalidated else {
            return task._process(.error(.pipelineInvalidated))
        }
        let worker = isDataTask ? makeTaskLoadData(for: task.request) : makeTaskLoadImage(for: task.request)
        task._subscription = worker.subscribe(priority: task.priority.taskPriority, subscriber: task) { [weak task] in
            task?._process($0)
        }
        tasks[ObjectIdentifier(task)] = task
        if !isDataTask {
            delegate.imageTask(task, didReceiveEvent: .started, pipeline: self)
        }
        onTaskStarted?(task)
    }

    // MARK: - Image Task Events

    func imageTaskCancelCalled(_ task: ImageTask) {
        tasks.removeValue(forKey: ObjectIdentifier(task))
        task._subscription?.unsubscribe()
        task._subscription = nil
        task._cancel()
    }

    func imageTaskUpdatePriorityCalled(_ task: ImageTask, priority: ImageRequest.Priority) {
        task._subscription?.setPriority(priority.taskPriority)
    }

    func imageTask(_ task: ImageTask, didProcessEvent event: ImageTask.Event, isDataTask: Bool) {
        switch event {
        case .finished:
            tasks.removeValue(forKey: ObjectIdentifier(task))
            task._subscription = nil
        default: break
        }

        if !isDataTask {
            delegate.imageTask(task, didReceiveEvent: event, pipeline: self)
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
            TaskFetchOriginalData(self, request)
        }
    }

}
