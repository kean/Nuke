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

    /// Initializes `DataLoader` with the given configuration.
    /// - parameter configuration: `URLSessionConfiguration.default` with
    /// `URLCache` with 0 MB memory capacity and 150 MB disk capacity.
    public init(configuration: URLSessionConfiguration = DataLoader.defaultConfiguration) {
        self.session = URLSession(configuration: configuration)
    }

    /// Returns a default configuration which has a `sharedUrlCache` set
    /// as a `urlCache`.
    public static var defaultConfiguration: URLSessionConfiguration {
        let conf = URLSessionConfiguration.default
        conf.urlCache = DataLoader.sharedUrlCache
        return conf
    }

    /// Shared url cached used by a default `DataLoader`.
    public static let sharedUrlCache = URLCache(
        memoryCapacity: 0,
        diskCapacity: 150 * 1024 * 1024, // 150 MB
        diskPath: "com.github.kean.Nuke.Cache"
    )

    /// Loads data with the given request.
    public func loadData(with request: Request, token: CancellationToken?, completion: @escaping (Result<(Data, URLResponse)>) -> Void) {
        let task = self.session.dataTask(with: request.urlRequest) { data, response, error in
            if let data = data, let response = response, error == nil {
                completion(.success((data, response)))
            } else {
                completion(.failure((error ?? NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil))))
            }
        }
        token?.register {
            task.cancel()
        }
        task.resume()
    }
}
