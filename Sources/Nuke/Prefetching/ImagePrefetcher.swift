// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Prefetches and caches images to eliminate delays when requesting the same
/// images later.
///
/// The prefetcher cancels all of the outstanding tasks when deallocated.
///
/// All ``ImagePrefetcher`` methods are thread-safe and are optimized to be used
/// even from the main thread during scrolling.
public final class ImagePrefetcher: Sendable {
    /// Pauses the prefetching.
    ///
    /// - note: When you pause, the prefetcher will finish outstanding tasks
    /// (by default, there are only 2 at a time), and pause the rest.
    public var isPaused: Bool {
        get { _isPaused.value }
        set {
            guard _isPaused.setValue(newValue) else { return }
            Task { @ImagePipelineActor in
                impl.queue.isSuspended = newValue
            }
        }
    }

    private let _isPaused = Mutex(false)

    /// The priority of the requests. By default, ``ImageRequest/Priority-swift.enum/low``.
    ///
    /// Changing the priority also changes the priority of all of the outstanding
    /// tasks managed by the prefetcher.
    public var priority: ImageRequest.Priority {
        get { _priority.value }
        set {
            guard _priority.setValue(newValue) else { return }
            Task { @ImagePipelineActor in
                impl.priority = newValue
            }
        }
    }

    private let _priority = Mutex(ImageRequest.Priority.low)

    /// Prefetching destination.
    public enum Destination: Sendable {
        /// Prefetches the image and stores it in both the memory and the disk
        /// cache (make sure to enable it).
        case memoryCache

        /// Prefetches the image data and stores it in disk caches. It does not
        /// require decoding the image data and therefore requires less CPU.
        ///
        /// - important: This option is incompatible with ``ImagePipeline/DataCachePolicy/automatic``
        /// (for requests with processors) and ``ImagePipeline/DataCachePolicy/storeEncodedImages``.
        case diskCache
    }

    /// An actor-isolated implementation.
    let impl: _ImagePrefetcher

    /// Initializes the ``ImagePrefetcher`` instance.
    ///
    /// - parameters:
    ///   - pipeline: The pipeline used for loading images.
    ///   - destination: By default load images in all cache layers.
    ///   - maxConcurrentRequestCount: 2 by default.
    public init(
        pipeline: ImagePipeline = ImagePipeline.shared,
        destination: Destination = .memoryCache,
        maxConcurrentRequestCount: Int = 2
    ) {
        self.impl = _ImagePrefetcher(pipeline: pipeline, destination: destination, maxConcurrentRequestCount: maxConcurrentRequestCount)
    }

    deinit {
        Task { @ImagePipelineActor [impl] in
            impl.stopPrefetching()
        }
    }

    /// Starts prefetching images for the given URL.
    ///
    /// See also ``startPrefetching(with:)-718dg`` that works with ``ImageRequest``.
    public func startPrefetching(with urls: [URL]) {
        Task { @ImagePipelineActor in
            for url in urls { impl.startPrefetching(with: url) }
        }
    }

    /// Starts prefetching images for the given requests.
    ///
    /// When you need to display the same image later, use the ``ImagePipeline``
    /// or the view extensions to load it as usual. The pipeline will take care
    /// of coalescing the requests to avoid any duplicate work.
    ///
    /// The priority of the requests is set to the priority of the prefetcher
    /// (`.low` by default).
    ///
    /// See also ``startPrefetching(with:)-1jef2`` that works with `URL`.
    public func startPrefetching(with requests: [ImageRequest]) {
        Task { @ImagePipelineActor in
            for request in requests { impl.startPrefetching(with: request) }
        }
    }

    /// Stops prefetching images for the given URLs and cancels outstanding
    /// requests.
    ///
    /// See also ``stopPrefetching(with:)-8cdam`` that works with ``ImageRequest``.
    public func stopPrefetching(with urls: [URL]) {
        Task { @ImagePipelineActor in
            for url in urls { impl.stopPrefetching(with: url) }
        }
    }

    /// Stops prefetching images for the given requests and cancels outstanding
    /// requests.
    ///
    /// You don't need to balance the number of `start` and `stop` requests.
    /// If you have multiple screens with prefetching, create multiple instances
    /// of ``ImagePrefetcher``.
    ///
    /// See also ``stopPrefetching(with:)-2tcyq`` that works with `URL`.
    public func stopPrefetching(with requests: [ImageRequest]) {
        Task { @ImagePipelineActor in
            for request in requests { impl.stopPrefetching(with: request) }
        }
    }

    /// Stops all prefetching tasks.
    public func stopPrefetching() {
        Task { @ImagePipelineActor in
            impl.stopPrefetching()
        }
    }
}

@ImagePipelineActor
final class _ImagePrefetcher: JobSubscriber {
    /// The closure that gets called when the prefetching completes for all the
    /// scheduled requests. The closure is always called on completion,
    /// regardless of whether the requests succeed or some fail.

    let pipeline: ImagePipeline
    let destination: ImagePrefetcher.Destination
    private var subscriptions = [TaskLoadImageKey: JobSubscription]()

    nonisolated let queue: JobQueue

    var priority: ImageRequest.Priority = .low

    nonisolated init(pipeline: ImagePipeline, destination: ImagePrefetcher.Destination, maxConcurrentRequestCount: Int) {
        self.pipeline = pipeline
        self.destination = destination
        self.queue = JobQueue(maxConcurrentJobCount: maxConcurrentRequestCount)
    }

    func startPrefetching(with url: URL) {
        startPrefetching(with: ImageRequest(url: url))
    }

    func startPrefetching(with request: ImageRequest) {
        var request = request
        if priority != request.priority {
            request.priority = priority
        }
        guard pipeline.cache[request] == nil else { return }

        let key = TaskLoadImageKey(request)
        guard subscriptions[key] == nil else { return }

        let job = ImagePrefetcherJob(prefetcher: self, request: request)
        job.queue = queue
        job.onDisposed = { [weak self] in
            self?.remove(key)
        }
        subscriptions[key] = job.subscribe(self)
        return
    }

    private func remove(_ key: TaskLoadImageKey) {
        subscriptions[key] = nil
    }

    func stopPrefetching(with url: URL) {
        stopPrefetching(with: ImageRequest(url: url))
    }

    func stopPrefetching(with request: ImageRequest) {
        if let subscription = subscriptions.removeValue(forKey: TaskLoadImageKey(request)) {
            subscription.unsubscribe()
        }
    }

    func stopPrefetching() {
        subscriptions.values.forEach { $0.unsubscribe() }
        subscriptions.removeAll()
    }

    @ImagePipelineActor
    private final class PrefetchTask {
        let key: TaskLoadImageKey
        weak var imageTask: ImageTask?
        var subscription: JobSubscription?

        init(key: TaskLoadImageKey) {
            self.key = key
        }

        // When task is cancelled, it is removed from the prefetcher and can
        // never get cancelled twice.
        func cancel() {
            subscription?.unsubscribe()
        }
    }

    // MARK: JobSubscriber

    // TODO: remove these
    func receive(_ event: Job<Void>.Event) {}
    func addSubscribedTasks(to output: inout [ImageTask]) {}
}

private final class ImagePrefetcherJob: Job<Void> {
    private weak var prefetcher: _ImagePrefetcher?
    private let request: ImageRequest
    private var task: Task<Void, Never>?

    init(prefetcher: _ImagePrefetcher, request: ImageRequest) {
        self.prefetcher = prefetcher
        self.request = request
        
        super.init()
    }

    override func start() {
        task = Task { @ImagePipelineActor in
            if let prefetcher {
                let imageTask = prefetcher.pipeline.makeImageTask(with: request, isDataTask: prefetcher.destination == .diskCache)
                _ = try? await imageTask.response
            }
            finish(with: .success(()))
        }
    }

    override func onCancel() {
        task?.cancel()
    }
}
