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

public extension Loading {
    /// Creates a task with with given request.
    func loadImage(with url: URL, token: CancellationToken? = nil) -> Promise<Image> {
        return loadImage(with: Request(url: url), token: token)
    }
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
    public let loader: DataLoading
    public let decoder: DataDecoding
    public let cache: Caching?
    public let schedulers: Schedulers
    
    /// Initializes `Loader` instance with the given data loader, decoder and
    /// cache. You could also provide loader with you own set of queues.
    /// - parameter schedulers: `Schedulers()` by default.
    public init(loader: DataLoading, decoder: DataDecoding, cache: Caching?, schedulers: Schedulers = Schedulers()) {
        self.loader = loader
        self.decoder = decoder
        self.cache = cache
        self.schedulers = schedulers
    }

    /// Loads an image for the given request using image loading pipeline.
    public func loadImage(with request: Request, token: CancellationToken? = nil) -> Promise<Image> {
        if request.memoryCacheOptions.readAllowed, let image = cache?.image(for: request) {
            return Promise(value: image)
        }
        return self.loader.loadData(with: request.urlRequest, token: token)
            .then { self.decode(data: $0, response: $1, token: token) }
            .then { self.process(image: $0, request: request, token: token) }
            .then {
                if request.memoryCacheOptions.writeAllowed {
                    self.cache?.setImage($0, for: request)
                }
        }
    }
    
    private func decode(data: Data, response: URLResponse, token: CancellationToken? = nil) -> Promise<Image> {
        return Promise() { fulfill, reject in
            schedulers.decoding.execute(token: token) {
                if let image = self.decoder.decode(data: data, response: response) {
                    fulfill(value: image)
                } else {
                    reject(error: DataDecoderFailed())
                }
            }
        }
    }

    private func process(image: Image, request: Request, token: CancellationToken?) -> Promise<Image> {
        guard let processor = request.processor else { return Promise(value: image) }
        return Promise() { fulfill, reject in
            schedulers.processing.execute(token: token) {
                if let image = processor.process(image) {
                    fulfill(value: image)
                } else {
                    reject(error: ProcessingFailed())
                }
            }
        }
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

// FIXME: move to enum
public struct DataDecoderFailed: Error {}
public struct ProcessingFailed: Error {}
