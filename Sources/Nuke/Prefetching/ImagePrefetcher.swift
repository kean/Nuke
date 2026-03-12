// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Prefetches and caches images to eliminate delays when requesting the same
/// images later.
///
/// The prefetcher cancels all of the outstanding tasks when deallocated.
///
/// All ``ImagePrefetcher`` methods are thread-safe and are optimized to be used
/// even from the main thread during scrolling.
@ImagePipelineActor
public final class ImagePrefetcher: Sendable {
    /// Pauses the prefetching.
    ///
    /// - note: When you pause, the prefetcher will finish outstanding tasks
    /// (by default, there are only 2 at a time), and pause the rest.
    nonisolated public var isPaused: Bool {
        get { queue.isSuspended }
        set { queue.isSuspended = newValue }
    }

    /// The priority of the requests. By default, ``ImageRequest/Priority-swift.enum/low``.
    ///
    /// Changing the priority also changes the priority of all of the outstanding
    /// tasks managed by the prefetcher.
    nonisolated public var priority: ImageRequest.Priority {
        get { _priority.value }
        set {
            guard _priority.value != newValue else { return }
            _priority.value = newValue
            Task { @ImagePipelineActor in self.didUpdatePriority(to: newValue) }
        }
    }
    private nonisolated let _priority = Mutex(value: ImageRequest.Priority.low)

    /// Prefetching destination.
    @frozen public enum Destination: Sendable {
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

    /// The closure that gets called when the prefetching completes for all the
    /// scheduled requests. The closure is always called on completion,
    /// regardless of whether the requests succeed or some fail.
    nonisolated(unsafe) public var didComplete: (@MainActor @Sendable () -> Void)?

    private let pipeline: ImagePipeline
    private let destination: Destination
    private var tasks = [TaskLoadImageKey: PrefetchTask]()
    let queue: TaskQueue // internal for testing

    /// Initializes the ``ImagePrefetcher`` instance.
    ///
    /// - parameters:
    ///   - pipeline: The pipeline used for loading images.
    ///   - destination: By default load images in all cache layers.
    ///   - maxConcurrentRequestCount: 2 by default.
    nonisolated public init(
        pipeline: ImagePipeline = ImagePipeline.shared,
        destination: Destination = .memoryCache,
        maxConcurrentRequestCount: Int = 2
    ) {
        self.pipeline = pipeline
        self.destination = destination
        self.queue = TaskQueue(maxConcurrentTaskCount: maxConcurrentRequestCount)
    }

    nonisolated deinit {
        let tasks = self.tasks.values
        Task { @ImagePipelineActor in
            for task in tasks {
                task.cancel()
            }
        }
    }

    /// Starts prefetching images for the given URL.
    ///
    /// See also ``startPrefetching(with:)-718dg`` that works with ``ImageRequest``.
    nonisolated public func startPrefetching(with urls: [URL]) {
        startPrefetching(with: urls.map { ImageRequest(url: $0) })
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
    nonisolated public func startPrefetching(with requests: [ImageRequest]) {
        Task { @ImagePipelineActor in
            self._startPrefetching(with: requests)
        }
    }

    private func _startPrefetching(with requests: [ImageRequest]) {
        let currentPriority = _priority.value
        for request in requests {
            var request = request
            if currentPriority != request.priority {
                request.priority = currentPriority
            }
            _startPrefetching(with: request)
        }
        sendCompletionIfNeeded()
    }

    private func _startPrefetching(with request: ImageRequest) {
        guard pipeline.cache[request] == nil else {
            return
        }
        let key = TaskLoadImageKey(request)
        guard tasks[key] == nil else {
            return
        }
        let task = PrefetchTask(request: request, key: key)
        let pipeline = self.pipeline
        let isDataTask = destination == .diskCache
        let operation = queue.add { [weak self] in
            let imageTask = pipeline.makeStartedImageTask(with: task.request, isDataTask: isDataTask)
            task.imageTask = imageTask
            _ = try? await imageTask.response
            self?._remove(task)
        }
        operation.priority = request.priority.taskPriority
        task.operation = operation
        tasks[key] = task
    }

    private func _remove(_ task: PrefetchTask) {
        guard tasks[task.key] === task else { return }
        tasks[task.key] = nil
        sendCompletionIfNeeded()
    }

    private func sendCompletionIfNeeded() {
        guard tasks.isEmpty, let callback = didComplete else {
            return
        }
        DispatchQueue.main.async(execute: callback)
    }

    /// Stops prefetching images for the given URLs and cancels outstanding
    /// requests.
    ///
    /// See also ``stopPrefetching(with:)-8cdam`` that works with ``ImageRequest``.
    nonisolated public func stopPrefetching(with urls: [URL]) {
        stopPrefetching(with: urls.map { ImageRequest(url: $0) })
    }

    /// Stops prefetching images for the given requests and cancels outstanding
    /// requests.
    ///
    /// You don't need to balance the number of `start` and `stop` requests.
    /// If you have multiple screens with prefetching, create multiple instances
    /// of ``ImagePrefetcher``.
    ///
    /// See also ``stopPrefetching(with:)-2tcyq`` that works with `URL`.
    nonisolated public func stopPrefetching(with requests: [ImageRequest]) {
        Task { @ImagePipelineActor in
            for request in requests {
                self._stopPrefetching(with: request)
            }
        }
    }

    private func _stopPrefetching(with request: ImageRequest) {
        if let task = tasks.removeValue(forKey: TaskLoadImageKey(request)) {
            task.cancel()
        }
    }

    /// Stops all prefetching tasks.
    nonisolated public func stopPrefetching() {
        Task { @ImagePipelineActor in
            self.tasks.values.forEach { $0.cancel() }
            self.tasks.removeAll()
        }
    }

    private func didUpdatePriority(to priority: ImageRequest.Priority) {
        let taskPriority = priority.taskPriority
        for task in tasks.values {
            task.imageTask?.priority = priority
            task.operation?.priority = taskPriority
        }
    }

    @ImagePipelineActor
    private final class PrefetchTask: Sendable {
        let key: TaskLoadImageKey
        let request: ImageRequest
        weak var imageTask: ImageTask?
        weak var operation: TaskQueue.Operation?

        init(request: ImageRequest, key: TaskLoadImageKey) {
            self.request = request
            self.key = key
        }

        // When task is cancelled, it is removed from the prefetcher and can
        // never get cancelled twice.
        func cancel() {
            operation?.cancel()
            imageTask?._cancelTask()
        }
    }
}
