// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Loads data.
public protocol DataLoading {
    /// Loads data with the given request.
    func loadData(with request: URLRequest, token: CancellationToken?, completion: @escaping (Result<(Data, URLResponse)>) -> Void)
}

/// Provides basic networking using `URLSession`.
public final class DataLoader: DataLoading {
    public private(set) var session: URLSession
    private let scheduler: AsyncScheduler
    
    /// Initializes `DataLoader` with the given configuration.
    /// - parameter configuration: `URLSessionConfiguration.default` with
    /// `URLCache` with 0 MB memory capacity and 150 MB disk capacity.
    /// - parameter scheduler: `OperationQueueScheduler` with `maxConcurrentOperationCount` 8 by default.
    /// Scheduler is wrapped in a `RateLimiter` to prevent `URLSession` trashing.
    public init(configuration: URLSessionConfiguration = DataLoader.defaultConfiguration(), scheduler: AsyncScheduler = RateLimiter(scheduler: OperationQueueScheduler(maxConcurrentOperationCount: 8))) {
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        self.scheduler = scheduler
    }
    
    private static func defaultConfiguration() -> URLSessionConfiguration {
        let conf = URLSessionConfiguration.default
        conf.urlCache = URLCache(memoryCapacity: 0, diskCapacity: (150 * 1024 * 1024), diskPath: "com.github.kean.Nuke.Cache")
        return conf
    }
    
    /// Loads data with the given request.
    public func loadData(with request: URLRequest, token: CancellationToken?, completion: @escaping (Result<(Data, URLResponse)>) -> Void) {
        scheduler.execute(token: token) { finish in
            let task = self.session.dataTask(with: request) { data, response, error in
                if let data = data, let response = response {
                    completion(.success((data, response)))
                } else {
                    completion(.failure((error ?? NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil))))
                }
                finish()
            }
            token?.register {
                task.cancel()
                finish()
            }
            task.resume()
        }
    }
}
