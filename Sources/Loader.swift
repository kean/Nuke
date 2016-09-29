// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Loads images.
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

/// `Loader` implements an image loading pipeline which consists of the
/// several steps:
///
/// 1. Read an image from the memory cache (if cache isn't `nil`). If the image
/// is found skip remaining steps.
/// 2. Load data using an object conforming to `DataLoading` protocol.
/// 3. Create an image with the data using `DataDecoding` object.
/// 4. Transform the image using processor (`Processing`) provided in the request.
/// 5. Save the image into the memory cache (if cache isn't `nil`).
///
/// See built-in `CachingDataLoader` class if you need to add custom data cache
/// into the pipeline.
///
/// `Loader` is thread-safe.
public final class Loader: Loading {
    public let loader: DataLoading
    public let decoder: DataDecoding
    public let cache: Caching?

    private let schedulers: Schedulers
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Loader")
    
    /// Returns a processor for the given image and request. Default
    /// implementation simply returns `request.processor`.
    public var makeProcessor: (Image, Request) -> AnyProcessor? = {
        return $1.processor
    }

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
        return queue.sync { promise(with: request, token: token) }
    }

    public func promise(with request: Request, token: CancellationToken? = nil) -> Promise<Image> {
        if request.memoryCacheOptions.readAllowed, let image = cache?[request] {
            return Promise(value: image)
        }
        // It's safe to capture `Loader` in promises
        return loader.loadData(with: request.urlRequest, token: token)
            .then(on: queue) { self.decode(data: $0, response: $1, token: token) }
            .then(on: queue) { self.process(image: $0, request: request, token: token) }
            .then(on: queue) {
                if request.memoryCacheOptions.writeAllowed {
                    self.cache?[request] = $0
                }
        }
    }

    private func decode(data: Data, response: URLResponse, token: CancellationToken? = nil) -> Promise<Image> {
        return Promise() { fulfill, reject in
            schedulers.decoding.execute(token: token) {
                if let image = self.decoder.decode(data: data, response: response) {
                    fulfill(image)
                } else {
                    reject(Error.decodingFailed)
                }
            }
        }
    }

    private func process(image: Image, request: Request, token: CancellationToken?) -> Promise<Image> {
        guard let processor = makeProcessor(image, request) else { return Promise(value: image) }
        return Promise() { fulfill, reject in
            schedulers.processing.execute(token: token) {
                if let image = processor.process(image) {
                    fulfill(image)
                } else {
                    reject(Error.processingFailed)
                }
            }
        }
    }

    /// Schedulers used to execute a corresponding steps of the pipeline.
    public struct Schedulers {
        /// `DispatchQueueScheduler` with a serial queue by default.
        public var decoding: Scheduler = DispatchQueueScheduler(queue: DispatchQueue(label: "com.github.kean.Nuke.Decoding"))
        // There is no reason to increase `maxConcurrentOperationCount` for
        // built-in `DataDecoder` that locks globally while decoding.
        
        /// `DispatchQueueScheduler` with a serial queue by default.
        public var processing: Scheduler = DispatchQueueScheduler(queue: DispatchQueue(label: "com.github.kean.Nuke.Processing"))
    }

    /// Error returns by `Loader` class itself. `Loader` might also return
    /// errors from underlying `DataLoading` object.
    public enum Error: Swift.Error {
        case decodingFailed
        case processingFailed
    }
}
