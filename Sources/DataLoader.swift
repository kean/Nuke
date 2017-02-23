// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Loads data.
public protocol DataLoading {
    /// Loads data with the given request.
    func loadData(with request: Request, token: CancellationToken?, completion: @escaping (Result<(Data, URLResponse)>) -> Void)
}

/// Provides basic networking using `URLSession`.
public final class DataLoader: DataLoading {
    public let session: URLSession
    private let scheduler: AsyncScheduler
    
    /// Initializes `DataLoader` with the given configuration.
    /// - parameter configuration: `URLSessionConfiguration.default` with
    /// `URLCache` with 0 MB memory capacity and 150 MB disk capacity.
    /// - parameter scheduler: `OperationQueueScheduler` with
    /// `maxConcurrentOperationCount` 6 by default.
    public init(configuration: URLSessionConfiguration = DataLoader.defaultConf,
                scheduler: AsyncScheduler = DataLoader.defaultScheduler) {
        self.session = URLSession(configuration: configuration)
        self.scheduler = scheduler
    }
    
    private static var defaultConf: URLSessionConfiguration {
        let conf = URLSessionConfiguration.default
        conf.urlCache = URLCache(
            memoryCapacity: 0,
            diskCapacity: 150 * 1024 * 1024, // 150 MB
            diskPath: "com.github.kean.Nuke.Cache"
        )
        return conf
    }
    
    private static var defaultScheduler: AsyncScheduler {
        return RateLimiter(scheduler: OperationQueueScheduler(maxConcurrentOperationCount: 6))
    }
    
    /// Loads data with the given request.
    public func loadData(with request: Request, token: CancellationToken?, completion: @escaping (Result<(Data, URLResponse)>) -> Void) {
        scheduler.execute(token: token) { finish in
            let task = self.session.dataTask(with: request.urlRequest) { data, response, error in
                if let data = data, let response = response, error == nil {
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
