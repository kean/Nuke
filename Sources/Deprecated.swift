import Foundation

// MARK: - Manager

@available(*, deprecated, message: "Please use Nuke `Nuke.loadImage(with:into:)` functions instead. To load images w/o targets please use `ImagePipeline`")
public final class Manager: Loading {
    public let loader: Loading
    public let cache: Caching?

    public static let shared: Nuke.Manager = Nuke.Manager(loader: Loader.shared, cache: ImageCache.shared)

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
        self.loadImage(with: ImageRequest(url: url), token: token, completion: completion)
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
private final class _LoadingImagePipleline: ImagePipeline {
    private let loader: Loading
    private let cache: Caching?

    init(loader: Loading, cache: Caching?) {
        self.loader = loader
        self.cache = cache
    }

    override func loadImage(with request: ImageRequest, completion: @escaping (Result<Image>) -> Void) -> Task {
        let cts = CancellationTokenSource()
        let task = _Task(cts: cts)

        if let image = self.cachedImage(for: request) {
            DispatchQueue.main.async { completion(.success(image)) }
        } else {
            self.loader.loadImage(with: request, token: cts.token) { result in
                if let image = result.value {
                    self.store(image: image, for: request)
                }
                DispatchQueue.main.async { completion(result) }
            }
        }
        return task
    }

    override func cachedImage(for request: ImageRequest) -> Image? {
        guard request.memoryCacheOptions.readAllowed else { return nil }
        return cache?[request]
    }

    override func store(image: Image, for request: ImageRequest) {
        guard request.memoryCacheOptions.writeAllowed else { return }
        cache?[request] = image
    }

    @available(*, deprecated, message: "For private use (silences warnings)")
    private final class _Task: Task {
        let cts: CancellationTokenSource
        init(cts: CancellationTokenSource) {
            self.cts = cts
        }

        override func cancel() {
            cts.cancel()
        }
    }
}

// MARK: - Loading

@available(*, deprecated, message: "Please use ImagePipeline class directly. There is no direct alternative to `Loading` protocol in Nuke 7.")
public protocol Loading {
    func loadImage(with request: ImageRequest, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void)
}

@available(*, deprecated, message: "Please use ImagePipeline class directly. There is no direct alternative to `Loading` protocol in Nuke 7.")
public extension Loading {
    public func loadImage(with request: ImageRequest, completion: @escaping (Result<Image>) -> Void) {
        self.loadImage(with: request, token: nil, completion: completion)
    }

    public func loadImage(with url: URL, token: CancellationToken? = nil, completion: @escaping (Result<Image>) -> Void) {
        self.loadImage(with: ImageRequest(url: url), token: token, completion: completion)
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
        public var processor: (Image, ImageRequest) -> AnyImageProcessor? = { $1.processor }

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

    public func loadImage(with request: ImageRequest, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        let task = pipeline.loadImage(with: request, completion: completion)
        token?.register { task.cancel() }
    }

    public typealias Error = ImagePipeline.Error
}

// MARK: - Preheater

extension ImagePreheater {
    @available(*, deprecated, message: "Please use init(pipeline:maxConcurrentRequestCount: instead")
    public convenience init(manager: Manager, maxConcurrentRequestCount: Int = 2) {
        self.init(pipeline: manager.pipeline, maxConcurrentRequestCount: maxConcurrentRequestCount)
    }
}

// MARK: - Renaming

@available(*, deprecated, message: "Please use `ImageRequest` instead")
public typealias Request = ImageRequest

@available(*, deprecated, message: "Please use `ImageCache` instead")
public typealias Cache = ImageCache

@available(*, deprecated, message: "Please use `ImageCaching` instead")
public typealias Caching = ImageCaching

@available(*, deprecated, message: "Please use `ImageProcessing` instead")
public typealias Processing = ImageProcessing

@available(*, deprecated, message: "Please use `ImageProcessorComposition` instead")
public typealias ProcessorComposition = ImageProcessorComposition

@available(*, deprecated, message: "Please use `AnyImageProcessor` instead")
public typealias AnyProcessor = AnyImageProcessor

@available(*, deprecated, message: "Please use `ImageDecompressor` instead")
public typealias Decompressor = ImageDecompressor

@available(*, deprecated, message: "Please use `ImagePreheater` instead")
public typealias Preheater = ImagePreheater

// MARK: - Deprecated ImagePipeline.Configuration Options

public extension ImagePipeline.Configuration {
/// The maximum number of concurrent data loading tasks. `6` by default.
    @available(*, deprecated, message: "Please set `maxConcurrentOperationCount` directly on `dataLoadingQueue`")
    public var maxConcurrentDataLoadingTaskCount: Int {
        get { return dataLoadingQueue.maxConcurrentOperationCount }
        set { dataLoadingQueue.maxConcurrentOperationCount = newValue }
    }

    /// The maximum number of concurrent image processing tasks. `2` by default.
    ///
    /// Parallelizing image processing might result in a performance boost
    /// in a certain scenarios, however it's not going to be noticable in most
    /// cases. Might increase memory usage.
    @available(*, deprecated, message: "Please set `maxConcurrentOperationCount` directly on `imageProcessingQueue`")
    public var maxConcurrentImageProcessingTaskCount: Int {
        get { return imageProcessingQueue.maxConcurrentOperationCount }
        set { imageProcessingQueue.maxConcurrentOperationCount = newValue }
    }

    @available(*, deprecated, message: "Please set `imageProcessor` instead`")
    public var processor: (Image, ImageRequest) -> AnyImageProcessor? {
        get { return imageProcessor }
        set { imageProcessor = newValue }
    }
}
