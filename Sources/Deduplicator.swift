// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Deduplicates equivalent requests.
///
/// If you attempt to load an image using `Deduplicator` more than once
/// before the initial load is complete, it would merge duplicate tasks. 
/// The image would be loaded only once, yet both completion handlers will
/// get called.
public final class Deduplicator: Loading {
    private let loader: Loading
    private let equator: RequestEquating
    private var tasks = [RequestKey: Task]()
    private let queue = DispatchQueue(label: "\(domain).Deduplicator")
    
    private final class Task {
        let promise: Promise<Image>
        let cts: CancellationTokenSource
        var retainCount = 0
        init(promise: Promise<Image>, cts: CancellationTokenSource) {
            self.promise = promise
            self.cts = cts
        }
    }
    
    /// Initializes the `Deduplicator` instance with the underlying
    /// `loader` used for loading images, and the request `equator`.
    /// - parameter loader: Underlying loader used for loading images.
    /// - parameter equator: Compares requests for equivalence.
    /// `RequestLoadingEquator()` be default.
    public init(with loader: Loading, equator: RequestEquating = RequestLoadingEquator()) {
        self.loader = loader
        self.equator = equator
    }
    
    public func loadImage(with request: Request, token: CancellationToken? = nil) -> Promise<Image> {
        return queue.sync {
            let key = RequestKey(request, equator: equator)
            var task: Task! = tasks[key] // Find existing promise
            if task == nil {
                let cts = CancellationTokenSource()
                let promise = loader.loadImage(with: request, token: cts.token)
                task = Task(promise: promise, cts: cts)
                tasks[key] = task
                promise.completion(on: self.queue) { _ in
                    if self.tasks[key] === task {
                        self.tasks[key] = nil
                    }
                }
            }
            
            task.retainCount += 1
            token?.register {
                self.queue.sync {
                    task.retainCount -= 1
                    if task.retainCount == 0 {
                        task.cts.cancel()
                        if self.tasks[key] === task {
                            self.tasks[key] = nil
                        }
                    }
                }
            }
            
            return task.promise
        }
    }
}
