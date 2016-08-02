// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Manages preheating (also known as prefetching, precaching) of images.
///
/// When you are working with many images, a `Preheater` can prepare images in
/// the background in order to eliminate delays when you later request
/// individual images. For example, use a `Preheater` when you want to populate
/// a collection view or similar UI with thumbnails.
///
/// To start preheating images call `startPreheating(for:)` method. When you
/// need an individual image just start loading an image using `Loading` object.
/// When preheating is no longer necessary call `stopPreheating(for:)` method.
public class Preheater {
    private let loader: Loading
    private let equator: RequestEquating
    private let scheduler: AsyncScheduler
    private let syncQueue = DispatchQueue(label: "\(domain).Preheater")
    private var tasks = [Task]()
        
    /// Initializes the `Preheater` instance with the `Loader` used for
    /// loading images, and the request `equator`.
    /// - parameter equator: Compares requests for equivalence.
    /// `RequestLoadingEquator()` be default.
    public init(loader: Loading, equator: RequestEquating = RequestLoadingEquator(), scheduler: AsyncScheduler = QueueScheduler(maxConcurrentOperationCount: 3)) {
        self.loader = loader
        self.equator = equator
        self.scheduler = scheduler
    }

    /// Prepares images for the given requests for later use.
    ///
    /// When you call this method, `Preheater` starts to load and cache images
    /// for the given requests. At any time afterward, you can create tasks
    /// for individual images with equivalent requests.
    public func startPreheating(for requests: [Request]) {
        syncQueue.async {
            requests.forEach { self.startPreheating(for: $0) }
        }
    }
    
    private func startPreheating(for request: Request) {
        // FIXME: use OrderedSet when Swift get it, array if fine for now
        // since we still do everything asynchronously
        if indexOfTask(with: request) == nil {
            let task = Task(request: request)
            let cts = CancellationTokenSource()
            scheduler.execute(token: cts.token) { [weak self] finish in
                self?.loader.loadImage(with: task.request, token: cts.token).completion { _ in
                    self?.syncQueue.async {
                        if let idx = self?.tasks.index(where: { task === $0 }) {
                            self?.tasks.remove(at: idx)
                        }
                    }
                    finish()
                }
                cts.token.register { finish() }
            }
            task.cts = cts
            tasks.append(task)
        }
    }
    
    /// Cancels image preparation for the given requests.
    public func stopPreheating(for requests: [Request]) {
        syncQueue.async {
            requests.forEach { request in
                if let index = self.indexOfTask(with: request) {
                    let task = self.tasks.remove(at: index)
                    task.cts?.cancel()
                }
            }
        }
    }
    
    private func indexOfTask(with request: Request) -> Int? {
        return tasks.index { equator.isEqual($0.request, to: request) }
    }

    /// Stops all preheating tasks.
    public func stopPreheating() {
        syncQueue.async {
            self.tasks.forEach { $0.cts?.cancel() }
            self.tasks.removeAll()
        }
    }

    private class Task {
        let request: Request
        var cts: CancellationTokenSource?
        init(request: Request) {
            self.request = request
        }
    }
}
