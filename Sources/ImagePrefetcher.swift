// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Prefetches and caches images to eliminate delays when requesting the same
/// images later.
///
/// To start prefetching, call `startPrefetching(with:)` method. When you need
/// the same image later to display it, just use the `ImagePipeline` or view
/// extensions to load the image. The pipeline will take care of coalescing the
/// requests for new without starting any new downloads.
///
/// The prefetcher automatically cancels all of the outstanding tasks when deallocated.
///
/// All `ImagePrefetcher` methods are thread-safe and are optimized to be used
/// even from the main thread during scrolling.
public final class ImagePrefetcher {
    private let pipeline: ImagePipeline
    /* private */ let queue = OperationQueue()
    private var tasks = [ImageRequest.LoadKeyForProcessedImage: Task]()
    private let destination: Destination

    /// Pauses the prefetching.
    ///
    /// - note: When you pause, the prefetcher will finish outstanding tasks
    /// (by default, there are only 2 at a time), and pause the rest.
    public var isPaused: Bool = false {
        didSet { queue.isSuspended = isPaused }
    }

    /// The priority of the requests. By default, `.low`.
    ///
    /// Changing the priority also changes the priority of all of the outstanding
    /// tasks managed by the prefetcher.
    public var priority: ImageRequest.Priority = .low {
        didSet {
            let newValue = priority
            pipeline.queue.async { self.didUpdatePriority(to: newValue) }
        }
    }
    private var _priority: ImageRequest.Priority = .low

    /// Prefetching destination.
    public enum Destination {
        /// Prefetches the image and stores it in both memory and disk caches
        /// (they should be enabled).
        case memoryCache

        /// Prefetches image data and stores it in disk caches. This does not
        /// require decoding the image data and therefore uses less CPU.
        case diskCache
    }

    /// Initializes the `ImagePrefetcher` instance.
    /// - parameter manager: `Loader.shared` by default.
    /// - parameter destination: `.memoryCache` by default.
    /// - parameter `maxConcurrentRequestCount`: 2 by default.
    public init(pipeline: ImagePipeline = ImagePipeline.shared,
                destination: Destination = .memoryCache,
                maxConcurrentRequestCount: Int = 2) {
        self.pipeline = pipeline
        self.destination = destination
        self.queue.maxConcurrentOperationCount = maxConcurrentRequestCount
        self.queue.underlyingQueue = pipeline.queue

        #if TRACK_ALLOCATIONS
        Allocations.increment("ImagePrefetcher")
        #endif
    }

    deinit {
        let tasks = self.tasks.values // Make sure we don't retain self
        pipeline.queue.async {
            for task in tasks {
                task.cancel()
            }
        }

        #if TRACK_ALLOCATIONS
        Allocations.decrement("ImagePrefetcher")
        #endif
    }

    /// Starts prefetching images for the given urls.
    ///
    /// The requests created by the prefetcher all have `.low` priority to make
    /// sure they don't interfere with the "regular" requests.
    ///
    /// - note: See `func startPrefetching(with requests: [ImageRequest])` for more info.
    public func startPrefetching(with urls: [URL]) {
        pipeline.queue.async {
            for url in urls {
                self._startPrefetching(with: self.makeRequest(url: url))
            }
        }
    }

    /// Starts prefetching images for the given requests.
    ///
    /// When you call this method, `ImagePrefetcher` starts to load and cache images
    /// for the given requests. When you need the same image later to display it,
    /// use the `ImagePipeline` or view extensions to load the image.
    /// The pipeline will take care of coalescing the requests for new without
    /// starting any new downloads.
    ///
    /// - note: Make sure to specify a low priority for your requests to ensure
    /// they don't interfere with the "regular" requests.
    public func startPrefetching(with requests: [ImageRequest]) {
        pipeline.queue.async {
            for request in requests {
                var request = request
                if request.priority > self._priority {
                    request.priority = self._priority
                }
                self._startPrefetching(with: request)
            }
        }
    }

    private func _startPrefetching(with request: ImageRequest) {
        let key = request.makeLoadKeyForFinalImage()

        guard tasks[key] == nil else {
            return // Already started prefetching
        }

        guard pipeline.configuration.imageCache?[request] == nil else {
            return // The image is already in memory cache
        }

        let task = Task(request: request, key: key)

        // Use `Operation` to limit maximum number of concurrent prefetch jobs
        task.operation = queue.add { [weak self, weak task] finish in
            guard let self = self, let task = task else {
                return finish()
            }
            self.loadImage(task: task, finish: finish)
        }
        tasks[key] = task
    }

    private func loadImage(task: Task, finish: @escaping () -> Void) {
        switch destination {
        case .diskCache:
            task.imageTask = pipeline.loadData(with: task.request, isConfined: true, queue: pipeline.queue, progress: nil) { [weak self] _ in
                self?._remove(task)
                finish()
            }
        case .memoryCache:
            task.imageTask = pipeline.loadImage(with: task.request, isConfined: true, queue: pipeline.queue, progress: nil) { [weak self] _ in
                self?._remove(task)
                finish()
            }
        }
        task.onCancelled = finish
    }

    private func _remove(_ task: Task) {
        guard tasks[task.key] === task else {
            return // Should never happen
        }
        tasks[task.key] = nil
    }

    /// Stops prefetching images for the given urls.
    public func stopPrefetching(with urls: [URL]) {
        pipeline.queue.async {
            for url in urls {
                self._stopPrefetching(with: self.makeRequest(url: url))
            }
        }
    }

    /// Stops prefetching images for the given requests and cancels outstanding
    /// requests.
    ///
    /// - note: You don't need to balance the number of `start` and `stop` requests.
    /// If you have multiple screens with prefetching, create multiple instances
    /// of `ImagePrefetcher`.
    ///
    /// - parameter destination: `.memoryCache` by default.
    public func stopPrefetching(with requests: [ImageRequest]) {
        pipeline.queue.async {
            for request in requests {
                self._stopPrefetching(with: request)
            }
        }
    }

    private func _stopPrefetching(with request: ImageRequest) {
        if let task = tasks.removeValue(forKey: request.makeLoadKeyForFinalImage()) {
            task.cancel()
        }
    }

    /// Stops all prefetching tasks.
    public func stopPrefetching() {
        pipeline.queue.async {
            self.tasks.values.forEach { $0.cancel() }
            self.tasks.removeAll()
        }
    }

    private func makeRequest(url: URL) -> ImageRequest {
        var request = ImageRequest(url: url)
        request.priority = _priority
        return request
    }

    private func didUpdatePriority(to priority: ImageRequest.Priority) {
        guard _priority != priority else {
            return
        }
        _priority = priority
        for task in tasks.values {
            task.imageTask?.priority = priority
        }
    }

    private final class Task {
        let key: ImageRequest.LoadKeyForProcessedImage
        let request: ImageRequest
        weak var imageTask: ImageTask?
        weak var operation: Operation?
        var onCancelled: (() -> Void)?

        init(request: ImageRequest, key: ImageRequest.LoadKeyForProcessedImage) {
            self.request = request
            self.key = key
        }

        // When task is cancelled, it is removed from the prefetcher and can
        // never get cancelled twice.
        func cancel() {
            operation?.cancel()
            imageTask?.cancel()
            onCancelled?()
        }
    }
}
