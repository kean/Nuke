// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Loads images.
public protocol Loading {
    /// Loads an image with the given request.
    ///
    /// Loader doesn't make guarantees on which thread the completion
    /// closure is called and whether it gets called or not after
    /// the operation gets cancelled.
    func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void)
}

public extension Loading {
    public func loadImage(with request: Request, completion: @escaping (Result<Image>) -> Void) {
        loadImage(with: request, token: nil, completion: completion)
    }
    
    /// Loads an image with the given url.
    public func loadImage(with url: URL, token: CancellationToken? = nil, completion: @escaping (Result<Image>) -> Void) {
        loadImage(with: Request(url: url), token: token, completion: completion)
    }
}

/// `Loader` implements an image loading pipeline:
///
/// 1. Load data using an object conforming to `DataLoading` protocol.
/// 2. Create an image with the data using `DataDecoding` object.
/// 3. Transform the image using processor (`Processing`) provided in the request.
///
/// `Loader` is thread-safe.
public final class Loader: Loading {
    private let loader: DataLoading
    private let decoder: DataDecoding
    private let schedulers: Schedulers
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Loader")
    
    /// Returns a processor for the given image and request. Default
    /// implementation simply returns `request.processor`.
    public var makeProcessor: (Image, Request) -> AnyProcessor? = {
        return $1.processor
    }

    /// Initializes `Loader` instance with the given loader, decoder and cache.
    /// - parameter decoder: `DataDecoder()` by default.
    /// - parameter schedulers: `Schedulers()` by default.
    public init(loader: DataLoading, decoder: DataDecoding = DataDecoder(), schedulers: Schedulers = Schedulers()) {
        self.loader = loader
        self.decoder = decoder
        self.schedulers = schedulers
    }

    /// Loads an image for the given request using image loading pipeline.
    public func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        queue.async {
            self.loader.loadData(with: request.urlRequest, token: token) { [weak self] in
                switch $0 {
                case let .success(val): self?.decode(data: val.0, response: val.1, request: request, token: token, completion: completion)
                case let .failure(err): completion(Result.failure(err))
                }
            }
        }
    }

    private func decode(data: Data, response: URLResponse, request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        queue.async {
            self.schedulers.decoding.execute(token: token) { [weak self] in
                if let image = self?.decoder.decode(data: data, response: response) {
                    self?.process(image: image, request: request, token: token, completion: completion)
                } else {
                    completion(Result.failure(Error.decodingFailed))
                }
            }
        }
    }
    
    private func process(image: Image, request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        queue.async {
            guard let processor = self.makeProcessor(image, request) else {
                completion(Result.success(image))
                return
            }
            self.schedulers.processing.execute(token: token) {
                if let image = processor.process(image) {
                    completion(Result.success(image))
                } else {
                    completion(Result.failure(Error.processingFailed))
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
