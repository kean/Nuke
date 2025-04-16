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

    private var tasks = Set<ImageTask>()

    private let tasksLoadData: TaskPool<TaskLoadImageKey, ImageResponse, ImageTask.Error>
    private let tasksLoadImage: TaskPool<TaskLoadImageKey, ImageResponse, ImageTask.Error>
    private let tasksFetchOriginalImage: TaskPool<TaskFetchOriginalImageKey, ImageResponse, ImageTask.Error>
    private let tasksFetchOriginalData: TaskPool<TaskFetchOriginalDataKey, (Data, URLResponse?), ImageTask.Error>

    private var isInvalidated = false

    private nonisolated let nextTaskId = Mutex<Int64>(0)

    let rateLimiter: RateLimiter?
    let id = UUID()

    @available(*, deprecated, message: "Please use ImageTask.Error")
    public typealias Error = ImageTask.Error

    deinit {
        Task { @ImagePipelineActor [id] in
            ResumableDataStorage.shared.unregister(id)
        }
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

        Task { @ImagePipelineActor [id] in
            ResumableDataStorage.shared.register(id)
        }
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
    public func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        tasks.forEach { $0._cancel() }
    }

    // MARK: - Loading Images

    /// Creates a task with the given URL.
    ///
    /// The task starts in a ``ImageTask/State-swift.enum/suspended`` state. It
    /// starts executing when you ask for the result or subscribe to ``ImageTask/events``.
    public nonisolated func imageTask(with url: URL) -> ImageTask {
        makeImageTask(with: ImageRequest(url: url))
    }

    /// Creates a task with the given request.
    ///
    /// The task starts in a ``ImageTask/State-swift.enum/suspended`` state. It
    /// starts executing when you ask for the result or subscribe to ``ImageTask/events``.
    public nonisolated func imageTask(with request: ImageRequest) -> ImageTask {
        makeImageTask(with: request)
    }

    /// Returns an image for the given URL.
    @inlinable
    public func image(for url: URL) async throws(ImageTask.Error) -> PlatformImage {
        try await image(for: ImageRequest(url: url))
    }

    /// Returns an image for the given request.
    @inlinable
    public func image(for request: ImageRequest) async throws(ImageTask.Error) -> PlatformImage {
        try await imageTask(with: request).image
    }

    // MARK: - Loading Data

    /// Returns image data for the given request.
    ///
    /// - parameter request: An image request.
    public func data(for request: ImageRequest) async throws(ImageTask.Error) -> (data: Data, response: URLResponse?) {
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

    func perform(_ task: ImageTask, onEvent: @escaping (AsyncTask<ImageResponse, ImageTask.Error>.Event) -> Void) -> TaskSubscription? {
        guard !isInvalidated else {
            onEvent(.error(.pipelineInvalidated))
            return nil
        }
        let worker = task.isDataTask ? makeTaskLoadData(for: task.request) : makeTaskLoadImage(for: task.request)
        tasks.insert(task)
        return worker.subscribe(priority: TaskPriority(task.priority), subscriber: task, onEvent)
    }

    func imageTask(_ task: ImageTask, didProcessEvent event: ImageTask.Event) {
        switch event {
        case .cancelled, .finished:
            tasks.remove(task)
        default: break
        }
        if !task.isDataTask {
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

    func makeTaskLoadImage(for request: ImageRequest) -> AsyncTask<ImageResponse, ImageTask.Error>.Publisher {
        tasksLoadImage.publisherForKey(TaskLoadImageKey(request)) {
            TaskLoadImage(self, request)
        }
    }

    func makeTaskLoadData(for request: ImageRequest) -> AsyncTask<ImageResponse, ImageTask.Error>.Publisher {
        tasksLoadData.publisherForKey(TaskLoadImageKey(request)) {
            TaskLoadData(self, request)
        }
    }

    func makeTaskFetchOriginalImage(for request: ImageRequest) -> AsyncTask<ImageResponse, ImageTask.Error>.Publisher {
        tasksFetchOriginalImage.publisherForKey(TaskFetchOriginalImageKey(request)) {
            TaskFetchOriginalImage(self, request)
        }
    }

    func makeTaskFetchOriginalData(for request: ImageRequest) -> AsyncTask<(Data, URLResponse?), ImageTask.Error>.Publisher {
        tasksFetchOriginalData.publisherForKey(TaskFetchOriginalDataKey(request)) {
            request.closure == nil ? TaskFetchOriginalData(self, request) : TaskFetchWithClosure(self, request)
        }
    }
}
