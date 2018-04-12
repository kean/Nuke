import Foundation

// MARK: - Manager

@available(*, deprecated, message: "Manager is deprecated, use Nuke global functions instead (e.g. `Nuke.loadImage(with:into:)`")
public final class Manager {
    /// Shared `Manager` instance.
    @available(*, deprecated, message: "Manager is deprecated, use Nuke global functions instead (e.g. `Nuke.loadImage(with:into:)`")
    public static let shared: Nuke.Manager = Nuke.Manager()

    @available(*, deprecated, message: "Manager is deprecated, use Nuke global functions instead (e.g. `Nuke.loadImage(with:into:)`")
    convenience init(loader: ImagePipeline, cache: Caching? = nil) {
        self.init(pipeline: loader)
    }

    fileprivate var pipeline: ImagePipeline {
        return _pipeline ?? ImagePipeline.shared
    }
    fileprivate var _pipeline: ImagePipeline?

    internal init(pipeline: ImagePipeline? = nil) {
        self._pipeline = pipeline
    }

    @available(*, deprecated, message: "Manager is deprecated, use Nuke global functions instead (e.g. `Nuke.loadImage(with:into:)`")
    public func loadImage(with url: URL, into target: Target) {
        Nuke.loadImage(with: url, pipeline: pipeline, into: target)
    }

    @available(*, deprecated, message: "Manager is deprecated, use Nuke global functions instead (e.g. `Nuke.loadImage(with:into:)`")
    public func loadImage(with request: Request, into target: Target) {
        Nuke.loadImage(with: request, pipeline: pipeline, into: target)
    }

    @available(*, deprecated, message: "Manager is deprecated, use Nuke global functions instead (e.g. `Nuke.loadImage(with:into:)`")
    public typealias Handler = (Result<Image>, _ isFromMemoryCache: Bool) -> Void

    @available(*, deprecated, message: "Manager is deprecated, use Nuke global functions instead (e.g. `Nuke.loadImage(with:into:)`")
    public func loadImage(with request: Request, into target: AnyObject, handler: @escaping Handler) {
        Nuke.loadImage(with: request, pipeline: pipeline, into: target, handler: handler)
    }

    @available(*, deprecated, message: "Manager is deprecated, use Nuke global functions instead (e.g. `Nuke.loadImage(with:into:)`")
    public func loadImage(with url: URL, into target: AnyObject, handler: @escaping Handler) {
        Nuke.loadImage(with: url, pipeline: pipeline, into: target, handler: handler)
    }

    @available(*, deprecated, message: "Manager is deprecated, use Nuke global functions instead (e.g. `Nuke.loadImage(with:into:)`")
    public func cancelRequest(for target: AnyObject) {
        Nuke.cancelRequest(for: target)
    }

    @available(*, deprecated, message: "Manager no longer implements Loading protocol.  loadImage(with:token:completion:) is deprecated. Use Loader methods instead")
    public func loadImage(with request: Request, token: CancellationToken? = nil, completion: @escaping (Result<Image>) -> Void) {
        let task = pipeline.loadImage(with: request, completion: completion)
        token?.register { task.cancel() }
    }

    @available(*, deprecated, message: "Manager no longer implements Loading protocol.  loadImage(with:token:completion:) is deprecated. Use Loader methods instead")
    public func loadImage(with url: URL, token: CancellationToken? = nil, completion: @escaping (Result<Image>) -> Void) {
        self.loadImage(with: Request(url: url), token: token, completion: completion)
    }

    @available(*, deprecated, message: "Manager no longer implements Loading protocol.  cachedImage(for:) is deprecated. Use Loader methods instead")
    public func cachedImage(for request: Request) -> Image? {
        return pipeline.cachedImage(for: request)
    }
}

// MARK: - Loading

@available(*, deprecated, message: "Loading protocol is deprecated, there is no alternative in Nuke 7. Please use ImagePipeline class directly.")
public protocol Loading {
    func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void)
}

@available(*, deprecated, message: "Loading protocol is deprecated, there is no alternative in Nuke 7. Please use ImagePipeline class directly.")
public extension Loading {

    @available(*, deprecated, message: "Loading protocol is deprecated, there is no alternative in Nuke 7. Please use ImagePipeline class directly.")
    public func loadImage(with request: Request, completion: @escaping (Result<Image>) -> Void) {
        self.loadImage(with: request, token: nil, completion: completion)
    }

    @available(*, deprecated, message: "Loading protocol is deprecated, there is no alternative in Nuke 7. Please use ImagePipeline class directly.")
    public func loadImage(with url: URL, token: CancellationToken? = nil, completion: @escaping (Result<Image>) -> Void) {
        self.loadImage(with: Request(url: url), token: token, completion: completion)
    }
}

@available(*, deprecated, message: "Loader is deprecated, please use ImagePipeline instead")
public final class Loader: Loading {

    @available(*, deprecated, message: "Loader is deprecated, please use ImagePipeline instead")
    public static let shared: Loading = Loader(loader: DataLoader())

    @available(*, deprecated, message: "Loader is deprecated, please use ImagePipeline instead")
    public struct Options {
        public var maxConcurrentDataLoadingTaskCount: Int = 6
        public var maxConcurrentImageProcessingTaskCount: Int = 2
        public var isDeduplicationEnabled = true
        public var isRateLimiterEnabled = true
        public var processor: (Image, Request) -> AnyProcessor? = { $1.processor }

        public init() {}
    }

    private let pipeline: ImagePipeline

    @available(*, deprecated, message: "Loader is deprecated, please use ImagePipeline instead")
    public init(loader: DataLoading, decoder: DataDecoding = DataDecoder(), options: Options = Options()) {
        self.pipeline = ImagePipeline {
            $0.dataLoader = loader
            $0.dataDecoder = decoder
            $0.maxConcurrentDataLoadingTaskCount = options.maxConcurrentDataLoadingTaskCount
            $0.maxConcurrentImageProcessingTaskCount = options.maxConcurrentImageProcessingTaskCount
            $0.isDeduplicationEnabled = options.isDeduplicationEnabled
            $0.isRateLimiterEnabled = options.isRateLimiterEnabled
            $0.processor = options.processor
        }
    }

    @available(*, deprecated, message: "Loader is deprecated, please use ImagePipeline instead")
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
