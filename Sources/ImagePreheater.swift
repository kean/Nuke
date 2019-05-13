// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Prefetches and caches image in order to eliminate delays when you request 
/// individual images later.
///
/// To start preheating call `startPreheating(with:)` method. When you
/// need an individual image just start loading an image using `Loading` object.
/// When preheating is no longer necessary call `stopPreheating(with:)` method.
///
/// All `Preheater` methods are thread-safe.
public final class ImagePreheater {
    private let pipeline: ImagePipeline
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Preheater")
    private let preheatQueue = OperationQueue()
    private var tasks = [ImageRequest.ImageLoadKey: Task]()
    private let destination: Destination

    /// Prefetching destination.
    public enum Destination {
        /// Prefetches the image and stores it both in memory and disk caches
        /// (in case they are enabled, naturally, there is no reason to prefetch
        /// unless they are).
        case memoryCache

        /// Prefetches image data and stores in disk cache. Will no decode
        /// the image data and will therefore useless less CPU.
        case diskCache
    }

    /// Initializes the `Preheater` instance.
    /// - parameter manager: `Loader.shared` by default.
    /// - parameter `maxConcurrentRequestCount`: 2 by default.
    /// - parameter destination: `.memoryCache` by default.
    public init(pipeline: ImagePipeline = ImagePipeline.shared,
                destination: Destination = .memoryCache,
                maxConcurrentRequestCount: Int = 2) {
        self.pipeline = pipeline
        self.destination = destination
        self.preheatQueue.maxConcurrentOperationCount = maxConcurrentRequestCount
    }

    /// Starte preheating images for the given urls.
    /// - note: See `func startPreheating(with requests: [ImageRequest])` for more info
    public func startPreheating(with urls: [URL]) {
        startPreheating(with: _requests(for: urls))
    }

    /// Starts preheating images for the given requests.
    ///
    /// When you call this method, `Preheater` starts to load and cache images
    /// for the given requests. At any time afterward, you can create tasks
    /// for individual images with equivalent requests.
    public func startPreheating(with requests: [ImageRequest]) {
        queue.async {
            for request in requests {
                self._startPreheating(with: self._updatedRequest(request))
            }
        }
    }

    private func _startPreheating(with request: ImageRequest) {
        let key = ImageRequest.ImageLoadKey(request: request)

        // Check if we we've already started preheating.
        guard tasks[key] == nil else {
            return
        }

        // Check if the image is already in memory cache.
        guard pipeline.configuration.imageCache?.cachedResponse(for: request) == nil else {
            return // already in memory cache
        }

        let task = Task(request: request, key: key)

        // Use `Operation` to limit maximum number of concurrent preheating jobs
        let operation = Operation(starter: { [weak self, weak task] finish in
            guard let self = self, let task = task else {
                return finish()
            }
            self.queue.async {
                self.loadImage(with: request, task: task, finish: finish)
            }
        })
        preheatQueue.addOperation(operation)
        tasks[key] = task
    }

    private func loadImage(with request: ImageRequest, task: Task, finish: @escaping () -> Void) {
        guard !task.isCancelled else {
            return finish()
        }
        let imageTask = pipeline.loadImage(with: request) { [weak self] _, _  in
            self?._remove(task)
            finish()
        }
        task.onCancelled = {
            imageTask.cancel()
            finish()
        }
    }

    private func _remove(_ task: Task) {
        queue.async {
            guard self.tasks[task.key] === task else {
                return
            }
            self.tasks[task.key] = nil
        }
    }

    /// Stops preheating images for the given urls.
    public func stopPreheating(with urls: [URL]) {
        stopPreheating(with: _requests(for: urls))
    }

    /// Stops preheating images for the given requests and cancels outstanding
    /// requests.
    ///
    /// - parameter destination: `.memoryCache` by default.
    public func stopPreheating(with requests: [ImageRequest]) {
        queue.async {
            for request in requests {
                self._stopPreheating(with: self._updatedRequest(request))
            }
        }
    }

    private func _stopPreheating(with request: ImageRequest) {
        if let task = tasks[ImageRequest.ImageLoadKey(request: request)] {
            tasks[task.key] = nil
            task.cancel()
        }
    }

    /// Stops all preheating tasks.
    public func stopPreheating() {
        queue.async {
            self.tasks.values.forEach { $0.cancel() }
            self.tasks.removeAll()
        }
    }

    private func _requests(for urls: [URL]) -> [ImageRequest] {
        return urls.map {
            var request = ImageRequest(url: $0)
            request.priority = .low
            return request
        }
    }

    private func _updatedRequest(_ request: ImageRequest) -> ImageRequest {
        guard destination == .diskCache else {
            return request // Avoid creating a new copy
        }

        var request = request
        // What we do under the hood is we disable decoding for the requests
        // that are meant to not be stored in memory cache.
        request.isDecodingDisabled = (destination == .diskCache)
        return request
    }

    private final class Task {
        let key: ImageRequest.ImageLoadKey
        let request: ImageRequest
        var isCancelled = false
        var onCancelled: (() -> Void)?
        weak var operation: Operation?

        init(request: ImageRequest, key: ImageRequest.ImageLoadKey) {
            self.request = request
            self.key = key
        }

        func cancel() {
            guard !isCancelled else { return }
            isCancelled = true
            operation?.cancel()
            onCancelled?()
        }
    }
}
