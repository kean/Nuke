// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Loads data.
public protocol DataLoading {
    /// Loads data with the given request.
    func loadData(with request: URLRequest, token: CancellationToken?) -> Promise<(Data, URLResponse)>
}

/// Provides basic networking using `URLSession`.
public final class DataLoader: DataLoading {
    public private(set) var session: URLSession
    private let scheduler: AsyncScheduler
    
    /// Initializes `DataLoader` with the given configuration.
    /// - parameter configuration: `URLSessionConfiguration.default` with
    /// `URLCache` with 0MB memory capacity and 200MB disk capacity.
    /// - parameter scheduler: `OperationQueueScheduler` with `maxConcurrentOperationCount` 8 by default.
    /// Scheduler is wrapped in a `RateLimiter` to prevent `URLSession` trashing.
    public init(configuration: URLSessionConfiguration = DataLoader.defaultConfiguration(), scheduler: AsyncScheduler = RateLimiter(scheduler: OperationQueueScheduler(maxConcurrentOperationCount: 8))) {
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        self.scheduler = scheduler
    }
    
    private static func defaultConfiguration() -> URLSessionConfiguration {
        let conf = URLSessionConfiguration.default
        conf.urlCache = URLCache(memoryCapacity: 0, diskCapacity: (200 * 1024 * 1024), diskPath: "com.github.kean.Nuke.Cache")
        return conf
    }

    /// Loads data with the given request.
    public func loadData(with request: URLRequest, token: CancellationToken? = nil) -> Promise<(Data, URLResponse)> {
        return Promise() { fulfill, reject in
            scheduler.execute(token: token) { finish in
                let task = self.session.dataTask(with: request) { data, response, error in
                    if let data = data, let response = response {
                        fulfill((data, response))
                    } else {
                        reject(error ?? NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil))
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
}

/// Stores `CachedURLResponse` objects.
public protocol DataCaching {
    /// Returns response for the given request.
    func response(for request: URLRequest, token: CancellationToken?) -> Promise<CachedURLResponse>
    
    /// Stores response for the given request.
    func setResponse(_ response: CachedURLResponse, for request: URLRequest)
}

public final class CachingDataLoader: DataLoading {
    private var loader: DataLoading
    private var cache: DataCaching

    public init(loader: DataLoading, cache: DataCaching) {
        self.loader = loader
        self.cache = cache
    }

    public func loadData(with request: URLRequest, token: CancellationToken?) -> Promise<(Data, URLResponse)> {
        return cache.response(for: request, token: token)
            .then { ($0.data, $0.response) }
            .recover { _ in
                self.loader.loadData(with: request, token: token).then {
                    self.cache.setResponse(CachedURLResponse(response: $0.1, data: $0.0), for: request)
                }
        }
    }
}
