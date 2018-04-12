import Foundation

// MARK: - Manager

@available(*, deprecated, message: "Please use Nuke `Nuke.loadImage(with:into:)` functions instead. To load images w/o targets please use `ImagePipeline`")
public final class Manager: Loading {
    public let loader: Loading
    public let cache: Caching?

    /// Shared `Manager` instance.
//    @available(*, deprecated, message: "Manager is deprecated, use Nuke global functions instead (e.g. `Nuke.loadImage(with:into:)`")
    public static let shared: Nuke.Manager = Nuke.Manager(loader: Loader.shared, cache: Cache.shared)

    fileprivate let pipeline: _LoadingImagePipleline

    public init(loader: Loading, cache: Caching? = nil) {
        self.loader = loader
        self.cache = cache
        self.pipeline = _LoadingImagePipleline(loader: loader, cache: cache)
    }

    public func loadImage(with url: URL, into target: Target) {
        Nuke.loadImage(with: url, pipeline: pipeline, into: target)
    }

    public func loadImage(with request: Request, into target: Target) {
        Nuke.loadImage(with: request, pipeline: pipeline, into: target)
    }

    public typealias Handler = (Result<Image>, _ isFromMemoryCache: Bool) -> Void

    public func loadImage(with request: Request, into target: AnyObject, handler: @escaping Handler) {
        Nuke.loadImage(with: request, pipeline: pipeline, into: target, handler: handler)
    }

    public func loadImage(with url: URL, into target: AnyObject, handler: @escaping Handler) {
        Nuke.loadImage(with: url, pipeline: pipeline, into: target, handler: handler)
    }

    public func cancelRequest(for target: AnyObject) {
        Nuke.cancelRequest(for: target)
    }

    public func loadImage(with url: URL, token: CancellationToken? = nil, completion: @escaping (Result<Image>) -> Void) {
        self.loadImage(with: Request(url: url), token: token, completion: completion)
    }

    public func loadImage(with request: Request, token: CancellationToken? = nil, completion: @escaping (Result<Image>) -> Void) {
        let task = pipeline.loadImage(with: request, completion: completion)
        token?.register { task.cancel() }
    }
}

// MARK: - _LoadingImagePipleline

// this types allow us to use deprecated `Loading` protocol with new global
// Nuke.loadImage(with:into:) functions.

@available(*, deprecated, message: "For private use (silences warnings)")
private final class _LoadingImagePiplelineTask: ImageTask {
    let cts: CancellationTokenSource
    init(cts: CancellationTokenSource) {
        self.cts = cts
    }

    override func cancel() {
        cts.cancel()
    }
}

@available(*, deprecated, message: "For private use (silences warnings)")
private final class _LoadingImagePipleline: ImagePipeline {
    private let loader: Loading
    private let cache: Caching?

    init(loader: Loading, cache: Caching?) {
        self.loader = loader
        self.cache = cache
    }

    override func loadImage(with request: Request, completion: @escaping (Result<Image>) -> Void) -> ImageTask {
        let cts = CancellationTokenSource()
        let task = _LoadingImagePiplelineTask(cts: cts)
        self.loader.loadImage(with: request, token: cts.token, completion: completion)
        return task
    }

    override func cachedImage(for request: Request) -> Image? {
        guard request.memoryCacheOptions.readAllowed else { return nil }
        return cache?[request]
    }

    override func store(image: Image, for request: Request) {
        guard request.memoryCacheOptions.writeAllowed else { return }
        cache?[request] = image
    }
}

// MARK: - Loading

@available(*, deprecated, message: "Please use ImagePipeline class directly. There is no direct alternative to `Loading` protocol in Nuke 7.")
public protocol Loading {
    func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void)
}

@available(*, deprecated, message: "Please use ImagePipeline class directly. There is no direct alternative to `Loading` protocol in Nuke 7.")
public extension Loading {
    public func loadImage(with request: Request, completion: @escaping (Result<Image>) -> Void) {
        self.loadImage(with: request, token: nil, completion: completion)
    }

    public func loadImage(with url: URL, token: CancellationToken? = nil, completion: @escaping (Result<Image>) -> Void) {
        self.loadImage(with: Request(url: url), token: token, completion: completion)
    }
}

@available(*, deprecated, message: "Please use `ImagePipeline` instead")
public final class Loader: Loading {

    public static let shared: Loading = Loader(loader: DataLoader())

    public struct Options {
        public var maxConcurrentDataLoadingTaskCount: Int = 6
        public var maxConcurrentImageProcessingTaskCount: Int = 2
        public var isDeduplicationEnabled = true
        public var isRateLimiterEnabled = true
        public var processor: (Image, Request) -> AnyProcessor? = { $1.processor }

        public init() {}
    }

    fileprivate let pipeline: ImagePipeline

    public init(loader: DataLoading, decoder: DataDecoding = DataDecoder(), options: Options = Options()) {
        self.pipeline = ImagePipeline {
            $0.dataLoader = loader
            $0.dataDecoder = decoder
            $0.imageCache = nil
            $0.maxConcurrentDataLoadingTaskCount = options.maxConcurrentDataLoadingTaskCount
            $0.maxConcurrentImageProcessingTaskCount = options.maxConcurrentImageProcessingTaskCount
            $0.isDeduplicationEnabled = options.isDeduplicationEnabled
            $0.isRateLimiterEnabled = options.isRateLimiterEnabled
            $0.processor = options.processor
        }
    }

    public func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        let task = pipeline.loadImage(with: request, completion: completion)
        token?.register { task.cancel() }
    }

    public typealias Error = ImagePipeline.Error
}

// MARK: - Preheater

extension Preheater {
    @available(*, deprecated, message: "Please use init(pipeline:maxConcurrentRequestCount: instead")
    public convenience init(manager: Manager = Manager.shared, maxConcurrentRequestCount: Int = 2) {
        self.init(pipeline: manager.pipeline, maxConcurrentRequestCount: maxConcurrentRequestCount)
    }
}
