// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Provides basic networking using `URLSession`.
public final class DataLoader: DataLoading, _DataLoaderObserving, @unchecked Sendable {
    public let session: URLSession
    private let impl = _DataLoader()

    @available(*, deprecated, message: "Please use `DataLoader/delegate` instead")
    public var observer: (any DataLoaderObserving)?

    /// Determines whether to deliver a partial response body in increments. By
    /// default, `false`.
    public var prefersIncrementalDelivery = false

    /// The delegate that gets called for the callbacks handled by the data loader.
    /// You can use it for observing the session events, but can't affect them.
    ///
    /// For example, you can use it to log network requests using [Pulse](https://github.com/kean/Pulse)
    /// which is optimized to work with images.
    ///
    /// ```swift
    /// (ImagePipeline.shared.configuration.dataLoader as? DataLoader)?.delegate = URLSessionProxyDelegate()
    /// ```
    ///
    /// - note: The delegate is retained.
    public var delegate: URLSessionDelegate? {
        didSet { impl.delegate = delegate }
    }

    deinit {
        session.invalidateAndCancel()

        #if TRACK_ALLOCATIONS
        Allocations.decrement("DataLoader")
        #endif
    }

    /// Initializes ``DataLoader`` with the given configuration.
    ///
    /// - parameters:
    ///   - configuration: `URLSessionConfiguration.default` with `URLCache` with
    ///   0 MB memory capacity and 150 MB disk capacity by default.
    ///   - validate: Validates the response. By default, check if the status
    ///   code is in the acceptable range (`200..<300`).
    public init(configuration: URLSessionConfiguration = DataLoader.defaultConfiguration,
                validate: @escaping (URLResponse) -> Swift.Error? = DataLoader.validate) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        self.session = URLSession(configuration: configuration, delegate: impl, delegateQueue: queue)
        self.session.sessionDescription = "Nuke URLSession"
        self.impl.validate = validate
        self.impl.observer = self

        #if TRACK_ALLOCATIONS
        Allocations.increment("DataLoader")
        #endif
    }

    /// Returns a default configuration which has a `sharedUrlCache` set
    /// as a `urlCache`.
    public static var defaultConfiguration: URLSessionConfiguration {
        let conf = URLSessionConfiguration.default
        conf.urlCache = DataLoader.sharedUrlCache
        return conf
    }

    /// Validates `HTTP` responses by checking that the status code is 2xx. If
    /// it's not returns ``DataLoader/Error/statusCodeUnacceptable(_:)``.
    public static func validate(response: URLResponse) -> Swift.Error? {
        guard let response = response as? HTTPURLResponse else {
            return nil
        }
        return (200..<300).contains(response.statusCode) ? nil : Error.statusCodeUnacceptable(response.statusCode)
    }

    #if !os(macOS) && !targetEnvironment(macCatalyst)
    private static let cachePath = "com.github.kean.Nuke.Cache"
    #else
    private static let cachePath: String = {
        let cachePaths = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
        if let cachePath = cachePaths.first, let identifier = Bundle.main.bundleIdentifier {
            return cachePath.appending("/" + identifier)
        }

        return ""
    }()
    #endif

    /// Shared url cached used by a default ``DataLoader``. The cache is
    /// initialized with 0 MB memory capacity and 150 MB disk capacity.
    public static let sharedUrlCache: URLCache = {
        let diskCapacity = 150 * 1048576 // 150 MB
        #if targetEnvironment(macCatalyst)
        return URLCache(memoryCapacity: 0, diskCapacity: diskCapacity, directory: URL(fileURLWithPath: cachePath))
        #else
        return URLCache(memoryCapacity: 0, diskCapacity: diskCapacity, diskPath: cachePath)
        #endif
    }()

    public func loadData(with request: URLRequest,
                         didReceiveData: @escaping (Data, URLResponse) -> Void,
                         completion: @escaping (Swift.Error?) -> Void) -> any Cancellable {
        let task = session.dataTask(with: request)
        if #available(iOS 14.5, tvOS 14.5, watchOS 7.4, macOS 11.3, *) {
            task.prefersIncrementalDelivery = prefersIncrementalDelivery
        }
        return impl.loadData(with: task, session: session, didReceiveData: didReceiveData, completion: completion)
    }

    /// Errors produced by ``DataLoader``.
    public enum Error: Swift.Error, CustomStringConvertible {
        /// Validation failed.
        case statusCodeUnacceptable(Int)

        public var description: String {
            switch self {
            case let .statusCodeUnacceptable(code):
                return "Response status code was unacceptable: \(code.description)"
            }
        }
    }

    // MARK: _DataLoaderObserving

    @available(*, deprecated, message: "Please use `DataLoader/delegate` instead")
    func dataTask(_ dataTask: URLSessionDataTask, didReceiveEvent event: DataTaskEvent) {
        observer?.dataLoader(self, urlSession: session, dataTask: dataTask, didReceiveEvent: event)
    }

    @available(*, deprecated, message: "Please use `DataLoader/delegate` instead")
    func task(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        observer?.dataLoader(self, urlSession: session, task: task, didFinishCollecting: metrics)
    }
}

// Actual data loader implementation. Hide NSObject inheritance, hide
// URLSessionDataDelegate conformance, and break retain cycle between URLSession
// and URLSessionDataDelegate.
private final class _DataLoader: NSObject, URLSessionDataDelegate {
    var validate: (URLResponse) -> Swift.Error? = DataLoader.validate
    private var handlers = [URLSessionTask: _Handler]()
    var delegate: URLSessionDelegate?
    weak var observer: (any _DataLoaderObserving)?

    /// Loads data with the given request.
    func loadData(with task: URLSessionDataTask,
                  session: URLSession,
                  didReceiveData: @escaping (Data, URLResponse) -> Void,
                  completion: @escaping (Error?) -> Void) -> any Cancellable {
        let handler = _Handler(didReceiveData: didReceiveData, completion: completion)
        session.delegateQueue.addOperation { // `URLSession` is configured to use this same queue
            self.handlers[task] = handler
        }
        task.taskDescription = "Nuke Load Data"
        task.resume()
        send(task, .resumed)
        return AnonymousCancellable { task.cancel() }
    }

    // MARK: URLSessionDelegate

#if swift(>=5.7)
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            (delegate as? URLSessionTaskDelegate)?.urlSession?(session, didCreateTask: task)
        } else {
            // Doesn't exist on earlier versions
        }
    }
#endif

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        (delegate as? URLSessionDataDelegate)?.urlSession?(session, dataTask: dataTask, didReceive: response, completionHandler: { _ in })
        send(dataTask, .receivedResponse(response: response))

        guard let handler = handlers[dataTask] else {
            completionHandler(.cancel)
            return
        }
        if let error = validate(response) {
            handler.completion(error)
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        (delegate as? URLSessionTaskDelegate)?.urlSession?(session, task: task, didCompleteWithError: error)

        assert(task is URLSessionDataTask)
        if let dataTask = task as? URLSessionDataTask {
            send(dataTask, .completed(error: error))
        }

        guard let handler = handlers[task] else {
            return
        }
        handlers[task] = nil
        handler.completion(error)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        (delegate as? URLSessionTaskDelegate)?.urlSession?(session, task: task, didFinishCollecting: metrics)
        observer?.task(task, didFinishCollecting: metrics)
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        (delegate as? URLSessionDataDelegate)?.urlSession?(session, dataTask: dataTask, didReceive: data)
        send(dataTask, .receivedData(data: data))

        guard let handler = handlers[dataTask], let response = dataTask.response else {
            return
        }
        // Don't store data anywhere, just send it to the pipeline.
        handler.didReceiveData(data, response)
    }

    // MARK: Internal

    private func send(_ dataTask: URLSessionDataTask, _ event: DataTaskEvent) {
        observer?.dataTask(dataTask, didReceiveEvent: event)
    }

    private final class _Handler {
        let didReceiveData: (Data, URLResponse) -> Void
        let completion: (Error?) -> Void

        init(didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) {
            self.didReceiveData = didReceiveData
            self.completion = completion
        }
    }
}
