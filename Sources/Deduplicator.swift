// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Combines requests with the same `loadKey` into a single request. This request
/// is only cancelled when all underlying requests are cancelled.
///
/// All `Deduplicator` methods are thread-safe.
public final class Deduplicator: Loading {
    private let loader: Loading
    private var tasks = [AnyHashable: Task]()
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Deduplicator")

    /// Initializes the `Deduplicator` instance with the underlying
    /// `loader` used for actual image loading, and the request `equator`.
    /// - parameter loader: Underlying loader used for loading images.
    public init(loader: Loading) {
        self.loader = loader
    }

    /// Returns an existing pending promise if there is one. Starts a new request otherwise.
    public func loadImage(with request: Request, token: CancellationToken? = nil) -> Promise<Image> {
        return queue.sync {
            let key = Request.loadKey(for: request)
            var task: Task! = tasks[key] // Find existing promise
            if task == nil {
                let cts = CancellationTokenSource()
                let promise = loader.loadImage(with: request, token: cts.token)
                task = Task(promise: promise, cts: cts)
                tasks[key] = task
                promise.completion(on: queue) { [weak self, weak task] _ in
                    if let task = task { self?.remove(task, key: key) }
                }
            } else {
                task.retainCount += 1
            }

            token?.register { [weak self, weak task] in
                if let task = task { self?.cancel(task, key: key) }
            }
            
            return task.promise
        }
    }
    
    private func cancel(_ task: Task, key: AnyHashable) {
        queue.async {
            task.retainCount -= 1
            if task.retainCount == 0 { // No more requests registered
                task.cts.cancel() // Cancel underlying request
                self.remove(task, key: key)
            }
        }
    }
    
    private func remove(_ task: Task, key: AnyHashable) {
        if tasks[key] === task { // Still managed by Deduplicator
            tasks[key] = nil
        }
    }

    private final class Task {
        let promise: Promise<Image>
        let cts: CancellationTokenSource
        var retainCount = 1
        init(promise: Promise<Image>, cts: CancellationTokenSource) {
            self.promise = promise
            self.cts = cts
        }
    }
}
