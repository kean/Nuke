// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Performs loading of images.
public protocol Loading {
    /// Loads an image with the given request.
    func loadImage(with request: Request, token: CancellationToken?) -> Promise<Image>
}

public extension Loading {
    /// Loads an image with the given URL.
    func loadImage(with url: URL, token: CancellationToken? = nil) -> Promise<Image> {
        return loadImage(with: Request(url: url), token: token)
    }
}

/// Performs loading of images.
///
/// `Loader` implements an image loading pipeline. First, data is loaded using
/// an object conforming to `DataLoading` protocol. Then data is decoded using
/// `DataDecoding` object. Decoded images are then processed by objects
/// conforming to `Processing` protocol which are provided by the `Request`.
///
/// You can initialize `Loader` with `Caching` object to add memory caching
/// into the pipeline.
public class Loader: Loading {
    public let loader: DataLoading
    public let decoder: DataDecoding
    public let cache: Caching?

    private let schedulers: Schedulers
    private let queue = DispatchQueue(label: "\(domain).Loader")

    /// Initializes `Loader` instance with the given loader, decoder and cache.
    /// - parameter schedulers: `Schedulers()` by default.
    public init(loader: DataLoading, decoder: DataDecoding, cache: Caching?, schedulers: Schedulers = Schedulers()) {
        self.loader = loader
        self.decoder = decoder
        self.cache = cache
        self.schedulers = schedulers
    }

    /// Loads an image for the given request using image loading pipeline.
    public func loadImage(with request: Request, token: CancellationToken? = nil) -> Promise<Image> {
        return Promise() { fulfill, reject in
            queue.async {
                self.loadImage(with: request, token: token, fulfill: fulfill, reject: reject)
            }
        }
    }

    private func loadImage(with request: Request, token: CancellationToken?,
                           fulfill: @escaping (Image) -> Void, reject: @escaping (Error) -> Void) {
        if request.memoryCacheOptions.readAllowed, let image = cache?[request] {
            fulfill(image)
            return
        }
        _ = loader.loadData(with: request.urlRequest, token: token)
            .then(on: queue) { self.decode(data: $0, response: $1, token: token) }
            .then(on: queue) { self.process(image: $0, request: request, token: token) }
            .then(on: queue) {
                if request.memoryCacheOptions.writeAllowed {
                    self.cache?[request] = $0
                }
                fulfill($0)
            }
            .catch(on: queue) { reject($0) }
    }

    private func decode(data: Data, response: URLResponse, token: CancellationToken? = nil) -> Promise<Image> {
        return Promise() { fulfill, reject in
            schedulers.decoding.execute(token: token) {
                if let image = self.decoder.decode(data: data, response: response) {
                    fulfill(image)
                } else {
                    reject(DecodingFailed())
                }
            }
        }
    }

    private func process(image: Image, request: Request, token: CancellationToken?) -> Promise<Image> {
        guard let processor = request.processor else { return Promise(value: image) }
        return Promise() { fulfill, reject in
            schedulers.processing.execute(token: token) {
                if let image = processor.process(image) {
                    fulfill(image)
                } else {
                    reject(ProcessingFailed())
                }
            }
        }
    }

    /// Schedulers used to execute a corresponding steps of the pipeline.
    public struct Schedulers {
        /// `DispatchQueueScheduler` with a serial queue by default.
        public var decoding: Scheduler = DispatchQueueScheduler(queue: DispatchQueue(label: "\(domain).Decoding"))
        // There is no reason to increase `maxConcurrentOperationCount` for
        // built-in `DataDecoder` that locks globally while decoding.
        
        /// `DispatchQueueScheduler` with a serial queue by default.
        public var processing: Scheduler = DispatchQueueScheduler(queue: DispatchQueue(label: "\(domain).Processing"))
    }
}

public struct DecodingFailed: Error {}
public struct ProcessingFailed: Error {}
