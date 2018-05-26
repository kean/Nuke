// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

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
    private var tasks = [PreheatKey: Task]()

    /// Initializes the `Preheater` instance.
    /// - parameter manager: `Loader.shared` by default.
    /// - parameter `maxConcurrentRequestCount`: 2 by default.
    public init(pipeline: ImagePipeline = ImagePipeline.shared, maxConcurrentRequestCount: Int = 2) {
        self.pipeline = pipeline
        self.preheatQueue.maxConcurrentOperationCount = maxConcurrentRequestCount
    }

    /// Preheats images for the given requests.
    ///
    /// When you call this method, `Preheater` starts to load and cache images
    /// for the given requests. At any time afterward, you can create tasks
    /// for individual images with equivalent requests.
    public func startPreheating(with requests: [ImageRequest]) {
        queue.async {
            requests.forEach(self._startPreheating)
        }
    }

    private func _startPreheating(with request: ImageRequest) {
        let key = PreheatKey(request: request)

        // Check if we we've already started preheating.
        guard tasks[key] == nil else { return }

        // Check if the image is already in memory cache.
        guard pipeline.configuration.imageCache?.cachedResponse(for: request) == nil else {
            return // already in memory cache
        }

        let task = Task(request: request, key: key)
        let token = task.cts.token

        let operation = Operation(starter: { [weak self] finish in
            let task = self?.pipeline.loadImage(with: request) { [weak self] _, _  in
                self?._remove(task)
                finish()
            }
            token.register {
                task?.cancel()
                finish()
            }
        })
        preheatQueue.addOperation(operation)
        token.register { [weak operation] in operation?.cancel() }

        tasks[key] = task
    }

    private func _remove(_ task: Task) {
        queue.async {
            guard self.tasks[task.key] === task else { return }
            self.tasks[task.key] = nil
        }
    }

    /// Stops preheating images for the given requests and cancels outstanding
    /// requests.
    public func stopPreheating(with requests: [ImageRequest]) {
        queue.async {
            requests.forEach(self._stopPreheating)
        }
    }

    private func _stopPreheating(with request: ImageRequest) {
        if let task = tasks[PreheatKey(request: request)] {
            tasks[task.key] = nil
            task.cts.cancel()
        }
    }

    /// Stops all preheating tasks.
    public func stopPreheating() {
        queue.async {
            self.tasks.forEach { $0.1.cts.cancel() }
            self.tasks.removeAll()
        }
    }

    private final class Task {
        let key: PreheatKey
        let request: ImageRequest
        let cts = _CancellationTokenSource()

        init(request: ImageRequest, key: PreheatKey) {
            self.request = request
            self.key = key
        }
    }

    private struct PreheatKey: Hashable {
        let cacheKey: ImageRequest.CacheKey
        let loadKey: ImageRequest.LoadKey

        init(request: ImageRequest) {
            self.cacheKey = ImageRequest.CacheKey(request: request)
            self.loadKey = ImageRequest.LoadKey(request: request)
        }

        #if !swift(>=4.1)
        var hashValue: Int {
            return cacheKey.hashValue
        }

        static func == (lhs: PreheatKey, rhs: PreheatKey) -> Bool {
            return lhs.cacheKey == rhs.cacheKey && lhs.loadKey == rhs.loadKey
        }
        #endif
    }
}
