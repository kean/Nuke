// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Loads data.
public protocol DataLoading {
    /// Loads data with the given request.
    func loadData(with request: URLRequest, token: CancellationToken?, progress: ProgressHandler?, completion: @escaping (Result<(Data, URLResponse)>) -> Void)
}

/// Provides basic networking using `URLSession`.
public final class DataLoader: DataLoading {
    public let session: URLSession
    private let validate: (Data, URLResponse) -> Swift.Error?
    private let controller = SessionController()
    private var resumableDataCache = _Cache<String, ResumableData>(costLimit: 32 * 1024 * 1024, countLimit: 100)

    /// Initializes `DataLoader` with the given configuration.
    /// - parameter configuration: `URLSessionConfiguration.default` with
    /// `URLCache` with 0 MB memory capacity and 150 MB disk capacity.
    public init(configuration: URLSessionConfiguration = DataLoader.defaultConfiguration, validate: @escaping (Data, URLResponse) -> Swift.Error? = DataLoader.validate) {
        self.session = URLSession(configuration: configuration, delegate: controller, delegateQueue: controller.queue)
        self.validate = validate
    }

    /// Returns a default configuration which has a `sharedUrlCache` set
    /// as a `urlCache`.
    public static var defaultConfiguration: URLSessionConfiguration {
        let conf = URLSessionConfiguration.default
        conf.urlCache = DataLoader.sharedUrlCache
        return conf
    }

    /// Validates `HTTP` responses by checking that the status code is 2xx. If
    /// it's not returns `DataLoader.Error.statusCodeUnacceptable`.
    public static func validate(data: Data, response: URLResponse) -> Swift.Error? {
        guard let response = response as? HTTPURLResponse else { return nil }
        return (200..<300).contains(response.statusCode) ? nil : Error.statusCodeUnacceptable(response.statusCode)
    }

#if os(macOS)
    private static let cachePath: String = {
        let cachePaths = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
        if let cachePath = cachePaths.first, let identifier = Bundle.main.bundleIdentifier {
            return cachePath.appending("/" + identifier)
        }

        return ""
    }()
#else
    private static let cachePath = "com.github.kean.Nuke.Cache"
#endif

    /// Shared url cached used by a default `DataLoader`. The cache is
    /// initialized with 0 MB memory capacity and 150 MB disk capacity.
    public static let sharedUrlCache = URLCache(
        memoryCapacity: 0,
        diskCapacity: 150 * 1024 * 1024, // 150 MB
        diskPath: cachePath
    )

    /// Loads data with the given request.
    public func loadData(with request: URLRequest, token: CancellationToken?, progress: ProgressHandler?, completion: @escaping (Result<(Data, URLResponse)>) -> Void) {
        // Needs to cleanup this code.

        let resumableData = request.url.flatMap {
            resumableDataCache.removeValue(forKey: $0.absoluteString)
        }
        let request = resumableData?.resumed(request: request) ?? request
        let task = session.dataTask(with: request)

        let validate = self.validate
        let handler = SessionTaskHandler(progress: progress) { [weak self] (data, response, error) in
            // Try to save resumable data in case the task was cancelled
            // (`URLError.cancelled`) or failed to complete with other error.
            if error != nil,
                let resumableData = ResumableData(response: task.response, data: data),
                let url = task.originalRequest?.url  {
                self?.resumableDataCache.set(resumableData, forKey: url.absoluteString, cost: data.count)
            }
            // Check if request failed with error
            if let error = error {
                completion(.failure(error))
                return
            }
            // Check if response & data non empty
            guard let response = response, !data.isEmpty else {
                completion(.failure(Error.responseEmpty))
                return
            }
            // Validate response
            if let error = validate(data, response) {
                completion(.failure(error))
                return
            }
            completion(.success((data, response)))
        }
        handler.data = resumableData?.data ?? Data()

        controller.register(handler, for: task)

        token?.register { [weak task] in task?.cancel() }
        task.resume()
    }

    /// Errors produced by `DataLoader`.
    public enum Error: Swift.Error, CustomDebugStringConvertible {
        /// Validation failed.
        case statusCodeUnacceptable(Int)
        /// Either the response or body was empty.
        case responseEmpty

        public var debugDescription: String {
            switch self {
            case let .statusCodeUnacceptable(code): return "Response status code was unacceptable: " + code.description // compiles faster than interpolation
            case .responseEmpty: return "Either the response or body was empty."
            }
        }
    }
}

private final class SessionController: NSObject, URLSessionDataDelegate {
    private let lock = NSLock()
    let queue = OperationQueue()
    private var handlers = [URLSessionTask: SessionTaskHandler]()

    override init() {
        queue.maxConcurrentOperationCount = 1
    }

    func register(_ handler: SessionTaskHandler, for task: URLSessionTask) {
        queue.addOperation { // `URLSession` is configured to use this same queue
            self.handlers[task] = handler
        }
    }

    // MARK: URLSessionDelegate

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let handler = handlers[task] else { return }
        handler.completion(handler.data, task.response, error)
        handlers[task] = nil
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let handler = handlers[dataTask] else { return }
        handler.data.append(data)
        handler.progress?(dataTask.countOfBytesReceived, dataTask.countOfBytesExpectedToReceive)
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

// Used to support resumable downloads.
private struct ResumableData {
    let data: Data
    let lastModified: String

    // Can only support partial downloads if `Accept-Ranges` is "bytes" and
    // `Last-Modified` is present.
    init?(response: URLResponse?, data: Data) {
        guard
            !data.isEmpty,
            let response = response as? HTTPURLResponse,
            response.statusCode == 200 /* OK */ || response.statusCode == 206 /* Partial Content */,
            let lastModified = response.allHeaderFields["Last-Modified"] as? String,
            let acceptRanges = response.allHeaderFields["Accept-Ranges"] as? String,
            acceptRanges.lowercased() == "bytes"
            else { return nil }

        // NOTE: https://developer.apple.com/documentation/foundation/httpurlresponse/1417930-allheaderfields
        // HTTP headers are case insensitive. To simplify your code, certain
        // header field names are canonicalized into their standard form.
        // For example, if the server sends a content-length header,
        // it is automatically adjusted to be Content-Length.

        self.data = data; self.lastModified = lastModified
    }

    func resumed(request: URLRequest) -> URLRequest {
        var request = request
        var headers = request.allHTTPHeaderFields ?? [:]
        headers["Range"] = "bytes=%tu-\(data.count)"
        headers["If-Range"] = lastModified
        request.allHTTPHeaderFields = headers
        return request
    }
}
