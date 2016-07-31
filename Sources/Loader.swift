// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Performs loading of images.
public protocol Loading {
    /// Loads an image for the given request.
    ///
    /// The implementation is not required to call the completion handler
    /// when the load gets cancelled.
    func loadImage(with request: Request, token: CancellationToken?) -> Promise<Image>
}

/// Performs loading of images.
///
/// `Loader` implements an image loading pipeline. First, data is loaded using
/// an object conforming to `DataLoading` protocol. Then data is decoded using
/// `DataDecoding` protocol. Decoded images are then processed by objects
/// conforming to `Processing` protocol which are provided by the `Request`.
///
/// You can initialize `Loader` with `DataCaching` object to add data caching
/// into the pipeline. Custom data cache might be more performant than caching
/// provided by `URL Loading System` (if that's what is used for loading).
public class Loader: Loading {
    public let cache: DataCaching?
    public let loader: DataLoading
    public let decoder: DataDecoding
    public let schedulers: Schedulers
    
    /// Initializes `Loader` instance with the given data loader, decoder and
    /// cache. You could also provide loader with you own set of queues.
    /// - parameter dataCache: `nil` by default.
    /// - parameter schedulers: `Schedulers()` by default.
    public init(loader: DataLoading, decoder: DataDecoding, cache: DataCaching? = nil, schedulers: Schedulers = Schedulers()) {
        self.loader = loader
        self.cache = cache
        self.decoder = decoder
        self.schedulers = schedulers
    }

    /// Loads an image for the given request using image loading pipeline.
    public func loadImage(with request: Request, token: CancellationToken? = nil) -> Promise<Image> {
        return loadData(with: request.urlRequest, token: token)
            .then { self.decoder.decode(data: $0, response: $1, scheduler: self.schedulers.decoding, token: token) }
            .then { self.process(image: $0, request: request, token: token) }
    }
    
    private func loadData(with request: URLRequest, token: CancellationToken?) -> Promise<(Data, URLResponse)> {
        if let cache = cache { // Chain that involes custom data caching
            return cache.response(for: request, token: token)
                .then { ($0.data, $0.response) }
                .recover { _ in self.loader.loadData(with: request, token: token) }
                .then { cache.setResponse(CachedURLResponse(response: $0.1, data: $0.0), for: request) }
        } else {
            return self.loader.loadData(with: request, token: token)
        }
    }
    
    private func process(image: Image, request: Request, token: CancellationToken?) -> Promise<Image> {
        guard let processor = request.processor else { return Promise(value: image) }
        return processor.process(image: image, scheduler: schedulers.processing, token: token)
    }
    
    /// Queues which are used to execute a corresponding steps of the pipeline.
    public struct Schedulers {
        /// `QueueScheduler` with `maxConcurrentOperationCount` 1 by default.
        public var decoding: Scheduler = QueueScheduler(maxConcurrentOperationCount: 1)
        // There is no reason to increase `maxConcurrentOperationCount` for
        // built-in `DataDecoder` that locks globally while decoding.
        
        /// `QueueScheduler` with `maxConcurrentOperationCount` 2 by default.
        public var processing: Scheduler = QueueScheduler(maxConcurrentOperationCount: 2)
    }
}
