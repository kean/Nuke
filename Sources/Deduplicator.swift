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
                promise.completion(on: self.queue) { [weak self, weak task] _ in
                    if let task = task, self?.tasks[key] === task {
                        self?.tasks[key] = nil
                    }
                }
            } else {
                task.retainCount += 1
            }

            token?.register { [weak self, weak task] in
                guard let task = task else { return }
                self?.queue.async {
                    task.retainCount -= 1
                    if task.retainCount == 0 {
                        task.cts.cancel() // cancel underlying request
                        if self?.tasks[key] === task {
                            self?.tasks[key] = nil
                        }
                    }
                }
            }
            
            return task.promise
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
