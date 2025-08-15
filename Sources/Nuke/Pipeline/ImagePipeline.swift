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

    private let jobsFetchImage: JobPool<TaskLoadImageKey, ImageResponse>
    private let jobsFetchData: JobPool<TaskFetchOriginalDataKey, (Data, URLResponse?)>

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
        self.jobsFetchImage = JobPool(isCoalescingEnabled)
        self.jobsFetchData = JobPool(isCoalescingEnabled)

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

    func perform(_ imageTask: ImageTask) -> JobSubscription? {
        guard !isInvalidated else {
            imageTask.receive(.error(.pipelineInvalidated))
            return nil
        }
        return imageTask.isDataTask ? performDataTask(imageTask) : performImageTask(imageTask)
    }

    // TODO: remove duplication
    private func performImageTask(_ imageTask: ImageTask) -> JobSubscription? {
        let task = JobPrefixFetchImage(self, imageTask.request)
        tasks.insert(imageTask)
        return task.subscribe(imageTask)
    }

    private func performDataTask(_ imageTask: ImageTask) -> JobSubscription? {
        let task = JobPrefixFetchData(self, imageTask.request)
        tasks.insert(imageTask)
        return task.subscribe(imageTask)
    }

    func imageTask(_ task: ImageTask, didProcessEvent event: ImageTask.Event) {
        switch event {
        case .cancelled, .finished:
            tasks.remove(task)
        default:
            break
        }
        if !task.isDataTask {
            delegate.imageTask(task, didReceiveEvent: event, pipeline: self)
        }
    }

    func makeJobFetchImage(for request: ImageRequest) -> Job<ImageResponse> {
        jobsFetchImage.task(for: TaskLoadImageKey(request)) {
            JobFetchImage(self, request)
        }
    }

    func makeJobFetchData(for request: ImageRequest) -> Job<(Data, URLResponse?)> {
        jobsFetchData.task(for: TaskFetchOriginalDataKey(request)) {
            let job = JobFetchData(self, request)
            // TODO: implement skipDataLoadingQueue
            // TODO: add separate operation for disk lookup (or no operation at all?)
            if request.options.contains(.skipDataLoadingQueue) {
                job.startIfNeeded()
            } else {
                job.queue = configuration.dataLoadingQueue
            }
            return job
        }
    }
}
