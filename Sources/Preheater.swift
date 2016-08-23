// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Manages preheating (prefetching, precaching) of images.
///
/// When you are working with a collection of images, a `Preheater` can prepare
/// images in the background in order to eliminate delays when you later request
/// individual images.
///
/// To start preheating images call `startPreheating(with:)` method. When you
/// need an individual image just start loading an image using `Loading` object.
/// When preheating is no longer necessary call `stopPreheating(with:)` method.
public class Preheater {
    private let loader: Loading
    private let scheduler: AsyncScheduler
    private let queue = DispatchQueue(label: "\(domain).Preheater")
    private var tasks = [Task]()
        
    /// Initializes the `Preheater` instance.
    /// - parameter loader: `Loader.shared` by default.
    /// - parameter scheduler: Throttles preheating requests. `QueueScheduler`
    /// with `maxConcurrentOperationCount` 2 by default.
    public init(loader: Loading = Loader.shared, scheduler: AsyncScheduler = QueueScheduler(maxConcurrentOperationCount: 2)) {
        self.loader = loader
        self.scheduler = scheduler
    }

    /// Prepares images for the given requests for later use.
    ///
    /// When you call this method, `Preheater` starts to load and cache images
    /// for the given requests. At any time afterward, you can create tasks
    /// for individual images with equivalent requests.
    public func startPreheating(with requests: [Request]) {
        queue.async {
            requests.forEach { self.startPreheating(with: $0) }
        }
    }
    
    private func startPreheating(with request: Request) {
        // FIXME: use OrderedSet when Swift stdlib has one
        if indexOfTask(with: request) == nil {
            let task = Task(request: request)
            scheduler.execute(token: task.cts.token) { [weak self] finish in
                self?.loader.loadImage(with: task.request, token: task.cts.token).completion { _ in
                    self?.queue.async {
                        if let idx = self?.tasks.index(where: { task === $0 }) {
                            self?.tasks.remove(at: idx)
                        }
                    }
                    finish()
                }
                task.cts.token.register { finish() }
            }
            tasks.append(task)
        }
    }
    
    /// Cancels image preparation for the given requests.
    public func stopPreheating(with requests: [Request]) {
        queue.async {
            requests.forEach { request in
                if let index = self.indexOfTask(with: request) {
                    let task = self.tasks.remove(at: index)
                    task.cts.cancel()
                }
            }
        }
    }
    
    private func indexOfTask(with request: Request) -> Int? {
        let key = Request.loadKey(for: request)
        return tasks.index { key == Request.loadKey(for: $0.request) }
    }

    /// Stops all preheating tasks.
    public func stopPreheating() {
        queue.async {
            self.tasks.forEach { $0.cts.cancel() }
            self.tasks.removeAll()
        }
    }

    private final class Task {
        let request: Request
        var cts = CancellationTokenSource()
        init(request: Request) {
            self.request = request
        }
    }
}
