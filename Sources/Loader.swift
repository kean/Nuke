// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

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
    /// Loads an image with the given request.
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

    /// Shared `Loading` object.
    ///
    /// Shared loader is created with `DataLoader()` wrapped in `Deduplicator`.
    public static let shared: Loading = Deduplicator(loader: Loader(loader: DataLoader()))

    /// Initializes `Loader` instance with the given loader, decoder.
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
            if token?.isCancelling == true { return } // Fast preflight check
            self.loadImage(with: Context(request: request, token: token, completion: completion))
        }
    }

    private func loadImage(with ctx: Context) {
        self.loader.loadData(with: ctx.request, token: ctx.token) { [weak self] in
            switch $0 {
            case let .success(val): self?.decode(response: val, context: ctx)
            case let .failure(err): ctx.completion(.failure(err))
            }
        }
    }

    private func decode(response: (Data, URLResponse), context ctx: Context) {
        queue.async {
            self.schedulers.decoding.execute(token: ctx.token) { [weak self] in
                if let image = self?.decoder.decode(data: response.0, response: response.1) {
                    self?.process(image: image, context: ctx)
                } else {
                    ctx.completion(.failure(Error.decodingFailed))
                }
            }
        }
    }

    private func process(image: Image, context ctx: Context) {
        queue.async {
            guard let processor = self.makeProcessor(image, ctx.request) else {
                ctx.completion(.success(image)) // no need to process
                return
            }
            self.schedulers.processing.execute(token: ctx.token) {
                if let image = processor.process(image) {
                    ctx.completion(.success(image))
                } else {
                    ctx.completion(.failure(Error.processingFailed))
                }
            }
        }
    }

    private struct Context {
        let request: Request
        let token: CancellationToken?
        let completion: (Result<Image>) -> Void
    }

    /// Schedulers used to execute a corresponding steps of the pipeline.
    public struct Schedulers {
        /// `DispatchQueueScheduler` with a serial queue by default.
        public var decoding: Scheduler = DispatchQueueScheduler(queue: DispatchQueue(label: "com.github.kean.Nuke.Decoding"))
        // There is no reason to increase `maxConcurrentOperationCount` for
        // built-in `DataDecoder` that locks globally while decoding.

        /// `DispatchQueueScheduler` with a serial queue by default.
        public var processing: Scheduler = DispatchQueueScheduler(queue: DispatchQueue(label: "com.github.kean.Nuke.Processing"))

        /// Creates a default `Schedulers`. instance.
        public init() {}
    }

    /// Error returns by `Loader` class itself. `Loader` might also return
    /// errors from underlying `DataLoading` object.
    public enum Error: Swift.Error {
        case decodingFailed
        case processingFailed
    }
}
