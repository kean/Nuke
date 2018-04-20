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
    private var tasks = [AnyHashable: Task]()

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
        let key = request.loadKey

        // Check if we we've already started preheating.
        guard tasks[key] == nil else { return }

        // Check if the image is already in memory cache.
        guard pipeline.configuration.imageCache?[request] == nil else { return }

        let task = Task(request: request, key: key)
        let token = task.cts.token

        let operation = Operation(starter: { [weak self] finish in
            let task = self?.pipeline.loadImage(with: request) { _ in
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
        if let task = tasks[request.loadKey] {
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
        let key: AnyHashable
        let request: ImageRequest
        let cts = _CancellationTokenSource()

        init(request: ImageRequest, key: AnyHashable) {
            self.request = request
            self.key = key
        }
    }
}
