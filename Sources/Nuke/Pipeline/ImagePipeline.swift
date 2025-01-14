// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// The pipeline downloads and caches images, and prepares them for display.
@ImagePipelineActor
public final class ImagePipeline {
    /// Returns the shared image pipeline.
    public nonisolated static var shared: ImagePipeline {
        get { _shared.value }
        set { _shared.value = newValue }
    }

    private nonisolated static let _shared = Mutex(ImagePipeline(configuration: .withURLCache))

    /// The pipeline configuration.
    public nonisolated let configuration: Configuration

    /// Provides access to the underlying caching subsystems.
    public nonisolated var cache: ImagePipeline.Cache { .init(pipeline: self) }

    let delegate: any ImagePipeline.Delegate

    private var tasks = [ImageTask: TaskSubscription]()

    private let tasksLoadData: TaskPool<TaskLoadImageKey, ImageResponse, Error>
    private let tasksLoadImage: TaskPool<TaskLoadImageKey, ImageResponse, Error>
    private let tasksFetchOriginalImage: TaskPool<TaskFetchOriginalImageKey, ImageResponse, Error>
    private let tasksFetchOriginalData: TaskPool<TaskFetchOriginalDataKey, (Data, URLResponse?), Error>

    private var isInvalidated = false

    private nonisolated let nextTaskId = Mutex<Int64>(0)

    let rateLimiter: RateLimiter?
    let id = UUID()

    // For testing purposes
    nonisolated(unsafe) var onTaskStarted: ((ImageTask) -> Void)?

    deinit {
        ResumableDataStorage.shared.unregister(id)
    }

    /// Initializes the instance with the given configuration.
    ///
    /// - parameters:
    ///   - configuration: The pipeline configuration.
    ///   - delegate: Provides more ways to customize the pipeline behavior on per-request basis.
    public nonisolated init(configuration: Configuration = Configuration(), delegate: (any ImagePipeline.Delegate)? = nil) {
        self.configuration = configuration
        self.rateLimiter = configuration.isRateLimiterEnabled ? RateLimiter() : nil
        self.delegate = delegate ?? ImagePipelineDefaultDelegate()
        (configuration.dataLoader as? DataLoader)?.prefersIncrementalDelivery = configuration.isProgressiveDecodingEnabled

        let isCoalescingEnabled = configuration.isTaskCoalescingEnabled
        self.tasksLoadData = TaskPool(isCoalescingEnabled)
        self.tasksLoadImage = TaskPool(isCoalescingEnabled)
        self.tasksFetchOriginalImage = TaskPool(isCoalescingEnabled)
        self.tasksFetchOriginalData = TaskPool(isCoalescingEnabled)

        ResumableDataStorage.shared.register(id)
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
    public nonisolated convenience init(delegate: (any ImagePipeline.Delegate)? = nil, _ configure: (inout ImagePipeline.Configuration) -> Void) {
        var configuration = ImagePipeline.Configuration()
        configure(&configuration)
        self.init(configuration: configuration, delegate: delegate)
    }

    /// Invalidates the pipeline and cancels all outstanding tasks. Any new
    /// requests will immediately fail with ``ImagePipeline/Error/pipelineInvalidated`` error.
    public nonisolated func invalidate() {
        Task { @ImagePipelineActor in
            guard !self.isInvalidated else { return }
            self.isInvalidated = true
            self.tasks.keys.forEach { cancelImageTask($0) }
        }
    }

    // MARK: - Loading Images

    /// Creates a task with the given URL.
    ///
    /// The task starts executing the moment it is created.
    public nonisolated func imageTask(with url: URL) -> ImageTask {
        imageTask(with: ImageRequest(url: url))
    }

    /// Creates a task with the given request.
    ///
    /// The task starts executing the moment it is created.
    public nonisolated func imageTask(with request: ImageRequest) -> ImageTask {
        makeImageTask(with: request)
    }

    /// Returns an image for the given URL.
    public func image(for url: URL) async throws -> PlatformImage {
        try await image(for: ImageRequest(url: url))
    }

    /// Returns an image for the given request.
    public func image(for request: ImageRequest) async throws -> PlatformImage {
        try await imageTask(with: request).image
    }

    // MARK: - Loading Data

    /// Returns image data for the given request.
    ///
    /// - parameter request: An image request.
    public func data(for request: ImageRequest) async throws -> (Data, URLResponse?) {
        let task = makeImageTask(with: request, isDataTask: true)
        let response = try await task.response
        return (response.container.data ?? Data(), response.urlResponse)
    }

    // MARK: - ImageTask (Internal)

    nonisolated func makeImageTask(with request: ImageRequest, isDataTask: Bool = false, onEvent: (@Sendable (ImageTask.Event, ImageTask) -> Void)? = nil) -> ImageTask {
        let task = ImageTask(taskId: nextTaskId.incremented(), request: request, isDataTask: isDataTask, pipeline: self, onEvent: onEvent)
        delegate.imageTaskCreated(task, pipeline: self)
        return task
    }

    // By this time, the task has `continuation` set and is fully wired.
    func startImageTask(_ task: ImageTask, isDataTask: Bool) {
        guard !isInvalidated else {
            return task.process(.error(.pipelineInvalidated))
        }
        let worker = isDataTask ? makeTaskLoadData(for: task.request) : makeTaskLoadImage(for: task.request)
        tasks[task] = worker.subscribe(priority: TaskPriority(task.priority), subscriber: task) { [weak task] in
            task?.process($0)
        }
        onTaskStarted?(task)
    }

    func cancelImageTask(_ task: ImageTask) {
        tasks.removeValue(forKey: task)?.unsubscribe()
        task._cancel()
    }

    func imageTask(_ task: ImageTask, didChangePriority priority: ImageRequest.Priority) {
        self.tasks[task]?.setPriority(TaskPriority(priority))
    }

    func imageTask(_ task: ImageTask, didProcessEvent event: ImageTask.Event, isDataTask: Bool) {
        switch event {
        case .cancelled, .finished:
            tasks[task] = nil
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
            request.closure == nil ? TaskFetchOriginalData(self, request) : TaskFetchWithClosure(self, request)
        }
    }
}
