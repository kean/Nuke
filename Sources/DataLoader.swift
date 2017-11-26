// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Loads data.
public protocol DataLoading {
    /// Loads data with the given request.
    func loadData(with request: URLRequest, token: CancellationToken?, progress: ProgressHandler?, completion: @escaping (Result<(Data, URLResponse)>) -> Void)
}

/// Provides basic networking using `URLSession`.
public final class DataLoader: DataLoading {
    public let session: URLSession
    private let delegate = SessionDelegate()

    /// Initializes `DataLoader` with the given configuration.
    /// - parameter configuration: `URLSessionConfiguration.default` with
    /// `URLCache` with 0 MB memory capacity and 150 MB disk capacity.
    public init(configuration: URLSessionConfiguration = DataLoader.defaultConfiguration) {
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: delegate.queue)
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
    public func loadData(with request: URLRequest, token: CancellationToken?, progress: ProgressHandler?, completion: @escaping (Result<(Data, URLResponse)>) -> Void) {
        let task = session.dataTask(with: request)
        let handler = SessionTaskHandler(progress: progress) { (data, response, error) in
            if let response = response, error == nil {
                completion(.success((data, response)))
            } else {
                completion(.failure((error ?? NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil))))
            }
        }
        delegate.register(handler, for: task)

        token?.register { task.cancel() }
        task.resume()
    }
}

private final class SessionDelegate: NSObject, URLSessionDataDelegate {
    private let lock = Lock()
    let queue = OperationQueue()
    private var handlers = [URLSessionTask: SessionTaskHandler]()

    override init() {
        queue.maxConcurrentOperationCount = 1
    }

    func register(_ handler: SessionTaskHandler, for task: URLSessionTask) {
        queue.addOperation {
            self.handlers[task] = handler
        }
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let handler = handlers[dataTask] {
            handler.data.append(data)
            handler.progress?(dataTask.countOfBytesReceived, dataTask.countOfBytesExpectedToReceive)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let handler = handlers[task] {
            handler.completion(handler.data, task.response, error)
            handlers[task] = nil
        }
    }
}

private final class SessionTaskHandler {
    var data = Data()
    let progress: ProgressHandler?
    let completion: (Data, URLResponse?, Error?) -> Void

    init(progress: ProgressHandler?, completion: @escaping (Data, URLResponse?, Error?) -> Void) {
        self.progress = progress
        self.completion = completion
    }
}
