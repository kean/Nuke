// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Performs loading of image data.
public protocol DataLoading {
    /// Creates a task with a given URL request.
    /// Task is resumed by the user that called the method.
    ///
    /// The implementation is not required to call the completion handler
    /// when the load gets cancelled.
    func loadData(with request: URLRequest, token: CancellationToken?) -> Promise<(Data, URLResponse)>
}

/// Provides basic networking using `URLSession`.
public final class DataLoader: DataLoading {
    public private(set) var session: URLSession
    private let scheduler: AsyncScheduler
    
    /// Initialzies data loader with a given configuration.
    /// - parameter scheduler: `QueueScheduler` with `maxConcurrentOperationCount` 8 by default.
    public init(configuration: URLSessionConfiguration = DataLoader.defaultConfiguration(), scheduler: AsyncScheduler = QueueScheduler(maxConcurrentOperationCount: 8)) {
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        self.scheduler = scheduler
    }
    
    private static func defaultConfiguration() -> URLSessionConfiguration {
        let conf = URLSessionConfiguration.default
        conf.urlCache = URLCache(memoryCapacity: 0, diskCapacity: (200 * 1024 * 1024), diskPath: "\(domain).Cache")
        return conf
    }
    
    /// Creates task for the given request.
    public func loadData(with request: URLRequest, token: CancellationToken? = nil) -> Promise<(Data, URLResponse)> {
        return Promise() { fulfill, reject in
            scheduler.execute(token: token) { [weak self] finish in
                let task = self?.session.dataTask(with: request) { data, response, error in
                    if let data = data, let response = response {
                        fulfill(value: (data, response))
                    } else {
                        let error = error ?? NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)
                        reject(error: error)
                    }
                    finish()
                }
                token?.register {
                    task?.cancel()
                    finish()
                }
                task?.resume()
            }
        }
    }
}

/// Provides in-disk storage for data.
///
/// Nuke doesn't provide a built-in implementation of this protocol.
/// However, it's very easy to implement one in an extension of some
/// existing library (like DFCache).
public protocol DataCaching {
    /// Returns response for the given request.
    func response(for request: URLRequest, token: CancellationToken?) -> Promise<CachedURLResponse>
    
    /// Stores response for the given request.
    func setResponse(_ response: CachedURLResponse, for request: URLRequest)
}
