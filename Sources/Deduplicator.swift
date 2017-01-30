// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Combines requests with the same `loadKey` into a single request. The request
/// only gets cancelled when all the underlying requests are cancelled.
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

    /// Combines requests with the same `loadKey` into a single request. The request
    /// only gets cancelled when all the underlying requests are cancelled.
    public func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        queue.async {
            self._loadImage(with: request, token: token, completion: completion)
        }
    }
    
    private func _loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        let key = Request.loadKey(for: request)
        let task = tasks[key] ?? startTask(with: request, key: key)

        task.retainCount += 1
        task.handlers.append(completion)

        token?.register { [weak self, weak task] in
            guard let task = task else { return }
            self?.queue.async { self?.cancel(task, key: key) }
        }
    }
    
    private func startTask(with request: Request, key: AnyHashable) -> Task {
        let task = Task()
        tasks[key] = task
        loader.loadImage(with: request, token: task.cts.token) { [weak self, weak task] result in
            guard let task = task else { return }
            self?.queue.async { self?.complete(task, key: key, result: result) }
        }
        return task
    }
    
    private func complete(_ task: Task, key: AnyHashable, result: Result<Image>) {
        guard tasks[key] === task else { return } // check if still registered
        task.handlers.forEach { $0(result) }
        tasks[key] = nil
    }
    
    private func cancel(_ task: Task, key: AnyHashable) {
        guard tasks[key] === task else { return } // check if still registered
        task.retainCount -= 1
        if task.retainCount == 0 {
            task.cts.cancel() // cancel underlying request
            tasks[key] = nil
        }
    }
    
    private final class Task {
        let cts = CancellationTokenSource()
        var handlers = [(Result<Image>) -> Void]()
        var retainCount = 0 // number of non-cancelled handlers
    }
}
