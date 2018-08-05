import Foundation

// MARK: - Manager

#if os(macOS)
import Cocoa
#elseif os(iOS) || os(tvOS)
import UIKit
#endif

/// Represents a target for image loading.
@available(*, deprecated, message: "Please use `ImageDisplaying` protocol instead")
public protocol Target: class {
    /// Callback that gets called when the request is completed.
    func handle(response: Result<Image>, isFromMemoryCache: Bool)
}

#if os(macOS)
import Cocoa
@available(*, deprecated, message: "This typealias is no longer used.")
public typealias ImageView = NSImageView
#elseif os(iOS) || os(tvOS)
import UIKit
@available(*, deprecated, message: "This typealias is no longer used.")
public typealias ImageView = UIImageView
#endif

#if os(macOS)
@available(*, deprecated, message: "Please use new `Nuke.loadImage(with:options:into:progress:completion)` functions instead.")
extension NSImageView: Target {
    /// Displays an image on success. Runs `opacity` transition if
    /// the response was not from the memory cache.
    public func handle(response: Result<Image>, isFromMemoryCache: Bool) {
        guard let image = response.value else { return }
        self.image = image
        if !isFromMemoryCache {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.duration = 0.25
            animation.fromValue = 0
            animation.toValue = 1
            let layer: CALayer? = self.layer // Make compiler happy on macOS
            layer?.add(animation, forKey: "imageTransition")
        }
    }
}
#endif

#if os(iOS) || os(tvOS)
@available(*, deprecated, message: "Please use new `Nuke.loadImage(with:options:into:progress:completion)` functions instead.")
extension UIImageView: Target {
    /// Displays an image on success. Runs `opacity` transition if
    /// the response was not from the memory cache.
    public func handle(response: Result<Image>, isFromMemoryCache: Bool) {
        guard let image = response.value else { return }
        self.image = image
        if !isFromMemoryCache {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.duration = 0.25
            animation.fromValue = 0
            animation.toValue = 1
            let layer: CALayer? = self.layer // Make compiler happy on macOS
            layer?.add(animation, forKey: "imageTransition")
        }
    }
}
#endif


@available(*, deprecated, message: "Please use new `Nuke.loadImage(with:options:into:progress:completion)` functions instead. Use new `ImagePipeline` to load images directly.")
public final class Manager: Loading {
    public let loader: Loading
    public let cache: Caching?

    public static let shared = Manager(loader: Loader.shared, cache: Cache.shared)

    public init(loader: Loading, cache: Caching? = nil) {
        self.loader = loader; self.cache = cache
    }

    public func loadImage(with request: Request, into target: Target) {
        loadImage(with: request, into: target) { [weak target] in
            target?.handle(response: $0, isFromMemoryCache: $1)
        }
    }

    public typealias Handler = (Result<Image>, _ isFromMemoryCache: Bool) -> Void

    public func loadImage(with request: Request, into target: AnyObject, handler: @escaping Handler) {
        assert(Thread.isMainThread)

        let context = getContext(for: target)
        context.cts?.cancel()
        context.cts = nil

        if let image = cachedImage(for: request) {
            handler(.success(image), true)
            return
        }

        let cts = CancellationTokenSource()
        context.cts = cts

        _loadImage(with: request, token: cts.token) { [weak context] in
            guard let context = context, context.cts === cts else { return }
            handler($0, false)
            context.cts = nil
        }
    }

    public func cancelRequest(for target: AnyObject) {
        assert(Thread.isMainThread)
        let context = getContext(for: target)
        context.cts?.cancel()
        context.cts = nil
    }

    public func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        if let image = cachedImage(for: request) {
            DispatchQueue.main.async { completion(.success(image)) }
        } else {
            _loadImage(with: request, token: token, completion: completion)
        }
    }

    private func _loadImage(with request: Request, token: CancellationToken? = nil, completion: @escaping (Result<Image>) -> Void) {
        loader.loadImage(with: request, token: token) { [weak self] result in
            if let image = result.value {
                self?.store(image: image, for: request)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func cachedImage(for request: Request) -> Image? {
        guard request.memoryCacheOptions.readAllowed else { return nil }
        return cache?[request]
    }

    private func store(image: Image, for request: Request) {
        guard request.memoryCacheOptions.writeAllowed else { return }
        cache?[request] = image
    }

    private static var contextAK = "Manager.Context.AssociatedKey"

    private func getContext(for target: AnyObject) -> Context {
        if let ctx = objc_getAssociatedObject(target, &Manager.contextAK) as? Context {
            return ctx
        }
        let ctx = Context()
        objc_setAssociatedObject(target, &Manager.contextAK, ctx, .OBJC_ASSOCIATION_RETAIN)
        return ctx
    }

    private final class Context {
        var cts: CancellationTokenSource?
        deinit { cts?.cancel() }
    }

    public func loadImage(with url: URL, into target: Target) {
        loadImage(with: Request(url: url), into: target)
    }

    public func loadImage(with url: URL, into target: AnyObject, handler: @escaping Handler) {
        loadImage(with: Request(url: url), into: target, handler: handler)
    }
}

// MARK: - Loading

@available(*, deprecated, message: "Please use new `ImagePipeline` class instead. There is no direct alternative to `Loading` protocol in Nuke 7.")
public protocol Loading {
    func loadImage(with request: ImageRequest, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void)
}

@available(*, deprecated, message: "Please use new `ImagePipeline` class instead. There is no direct alternative to `Loading` protocol in Nuke 7.")
public extension Loading {
    public func loadImage(with request: ImageRequest, completion: @escaping (Result<Image>) -> Void) {
        self.loadImage(with: request, token: nil, completion: completion)
    }

    public func loadImage(with url: URL, token: CancellationToken? = nil, completion: @escaping (Result<Image>) -> Void) {
        self.loadImage(with: ImageRequest(url: url), token: token, completion: completion)
    }
}

@available(*, deprecated, message: "Please use new `ImagePipeline` class instead")
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
            $0.imageDecoder = {
                // empty URL response path never going to be executed because
                // it's only possible with a new DataCaching infrastructure
                // which can only be used with ImagePipeline and ImageDecoding
                return _DataDecoderAdapter(decoder: decoder, response: $0.urlResponse ?? URLResponse())
            }
            // In the previous Manager-Loader infrastructure Loader didn't have
            // a memory cache.
            $0.imageCache = nil

            $0.dataLoadingQueue.maxConcurrentOperationCount = options.maxConcurrentDataLoadingTaskCount
            $0.imageProcessingQueue.maxConcurrentOperationCount = options.maxConcurrentImageProcessingTaskCount
            $0.isDeduplicationEnabled = options.isDeduplicationEnabled
            $0.isRateLimiterEnabled = options.isRateLimiterEnabled
            $0.imageProcessor = options.processor
        }
    }

    public func loadImage(with request: ImageRequest, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        let task = pipeline.loadImage(with: request) { response, error in
            if let response = response {
                completion(.success(response.image))
            } else {
                completion(.failure(error ?? ImagePipeline.Error.decodingFailed))
                // we pass `ImagePipeline.Error.decodingFailed` to make this
                //  compile, in reality pipeline always returns an error.
            }
        }
        token?.register { task.cancel() }
    }

    public typealias Error = ImagePipeline.Error
}

// MARK: - ImageRequest

public extension ImageRequest {
    @available(*, deprecated, message: "Please use `ImageTask` delegate instead. Settings this property will have no effect.`")
    public var progress: ProgressHandler? {
        get { return nil }
        set { }
    }
}

// MARK: - Caching

@available(*, deprecated, message: "Please use `ImageCaching` instead.")
public protocol Caching: class {
    subscript(key: AnyHashable) -> Image? { get set }
}

@available(*, deprecated, message: "Please use `ImageCaching` instead.")
public extension Caching {
    /// Accesses the image associated with the given request.
    public subscript(request: ImageRequest) -> Image? {
        get { return self[AnyHashable(ImageRequest.CacheKey(request: request))] }
        set { self[AnyHashable(ImageRequest.CacheKey(request: request))] = newValue }
    }
}

@available(*, deprecated, message: "Please use `ImageCache` instead.")
public final class Cache: Caching {
    private let _impl: _Cache<AnyHashable, Image>

    public var costLimit: Int {
        get { return _impl.costLimit }
        set { _impl.costLimit = newValue }
    }

    public var countLimit: Int {
        get { return _impl.countLimit }
        set { _impl.countLimit = newValue }
    }

    public var totalCost: Int { return _impl.totalCost }
    public var totalCount: Int { return _impl.totalCount }

    public static let shared = Cache()

    public init(costLimit: Int = Cache.defaultCostLimit(), countLimit: Int = Int.max) {
        _impl = _Cache(costLimit: costLimit, countLimit: countLimit)
    }

    public static func defaultCostLimit() -> Int {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let ratio = physicalMemory <= (536_870_912 /* 512 Mb */) ? 0.1 : 0.2
        let limit = physicalMemory / UInt64(1 / ratio)
        return limit > UInt64(Int.max) ? Int.max : Int(limit)
    }

    // MARK: ImageCaching

    public func cachedResponse(for request: ImageRequest) -> ImageResponse? {
        guard let image = self[ImageRequest.CacheKey(request: request)] else { return nil }
        return ImageResponse(image: image, urlResponse: nil) // we don't have urlResponse
    }

    public func storeResponse(_ response: ImageResponse, for request: ImageRequest) {
        self[ImageRequest.CacheKey(request: request)] = response.image
    }

    public func removeResponse(for request: ImageRequest) {
        self[ImageRequest.CacheKey(request: request)] = nil
    }

    // MARK: Caching

    public subscript(key: AnyHashable) -> Image? {
        get { return _impl.value(forKey: key) }
        set {
            guard let newValue = newValue else {
                _impl.removeValue(forKey: key)
                return
            }
            _impl.set(newValue, forKey: key, cost: self.cost(newValue))
        }
    }

    public func removeAll() {
        _impl.removeAll()
    }

    public func trim(toCost limit: Int) {
        _impl.trim(toCost: limit)
    }

    public func trim(toCount limit: Int) {
        _impl.trim(toCount: limit)
    }

    public var cost: (Image) -> Int = {
        #if os(macOS)
        return 1
        #else
        // bytesPerRow * height gives a rough estimation of how much memory
        // image uses in bytes. In practice this algorithm combined with a
        // concervative default cost limit works OK.
        guard let cgImage = $0.cgImage else {
            return 1
        }
        return cgImage.bytesPerRow * cgImage.height
        #endif
    }
}

// MARK: - Renaming

@available(*, deprecated, message: "It was renamed into `ImageRequest`.")
public typealias Request = ImageRequest

@available(*, deprecated, message: "Please use new `ImageTask.ProgressHandler` typealias instead.")
public typealias ProgressHandler = ImageTask.ProgressHandler

// MARK: - DataDecoding

@available(*, deprecated, message: "Please use new `ImageDecoding` protocol instead.")
public protocol DataDecoding {
    /// Decodes image data.
    func decode(data: Data, response: URLResponse) -> Image?
}

@available(*, deprecated, message: "Please use `ImageDecoder` instead.")
public struct DataDecoder: DataDecoding {
    /// Initializes the receiver.
    public init() {}

    /// Creates an image with the given data.
    public func decode(data: Data, response: URLResponse) -> Image? {
        return _decode(data)
    }
}

@available(*, deprecated, message: "Please use new `ImageDecoderRegistry` class to register custom decoders.")
public struct DataDecoderComposition: DataDecoding {
    public let decoders: [DataDecoding]

    /// Composes multiple data decoders.
    public init(decoders: [DataDecoding]) {
        self.decoders = decoders
    }

    /// Decoders are applied in order in which they are present in the decoders
    /// array. The decoding stops when one of the decoders produces an image.
    public func decode(data: Data, response: URLResponse) -> Image? {
        for decoder in decoders {
            if let image = decoder.decode(data: data, response: response) {
                return image
            }
        }
        return nil
    }
}

@available(*, deprecated, message: "Please use `ImageDecoding` infrastructure instead.")
internal final class _DataDecoderAdapter: ImageDecoding {
    private let response: URLResponse
    private let decoder: DataDecoding

    init(decoder: DataDecoding, response: URLResponse) {
        self.decoder = decoder
        self.response = response
    }

    func decode(data: Data, isFinal: Bool) -> Image? {
        return decoder.decode(data: data, response: response)
    }
}

// MARK: - CancellationTokenSource

/// Manages cancellation tokens and signals them when cancellation is requested.
///
/// All `CancellationTokenSource` methods are thread safe.
@available(*, deprecated, message: "If you'd like to continue using cancellation tokens please consider copying this code into your project.")
public final class CancellationTokenSource {
    /// Returns `true` if cancellation has been requested.
    public var isCancelling: Bool {
        return _lock.sync { _observers == nil }
    }

    /// Creates a new token associated with the source.
    public var token: CancellationToken {
        return CancellationToken(source: self)
    }

    private var _observers: ContiguousArray<() -> Void>? = []

    /// Initializes the `CancellationTokenSource` instance.
    public init() {}

    fileprivate func register(_ closure: @escaping () -> Void) {
        if !_register(closure) {
            closure()
        }
    }

    private func _register(_ closure: @escaping () -> Void) -> Bool {
        _lock.lock(); defer { _lock.unlock() }
        _observers?.append(closure)
        return _observers != nil
    }

    /// Communicates a request for cancellation to the managed tokens.
    public func cancel() {
        if let observers = _cancel() {
            observers.forEach { $0() }
        }
    }

    private func _cancel() -> ContiguousArray<() -> Void>? {
        _lock.lock(); defer { _lock.unlock() }
        let observers = _observers
        _observers = nil // transition to `isCancelling` state
        return observers
    }
}

// We use the same lock across different tokens because the design of CTS
// prevents potential issues. For example, closures registered with a token
// are never executed inside a lock.
private let _lock = NSLock()

/// Enables cooperative cancellation of operations.
///
/// You create a cancellation token by instantiating a `CancellationTokenSource`
/// object and calling its `token` property. You then pass the token to any
/// number of threads, tasks, or operations that should receive notice of
/// cancellation. When the owning object calls `cancel()`, the `isCancelling`
/// property on every copy of the cancellation token is set to `true`.
/// The registered objects can respond in whatever manner is appropriate.
///
/// All `CancellationToken` methods are thread safe.
@available(*, deprecated, message: "If you'd like to continue using cancellation tokens please consider copying this code into your project.")
public struct CancellationToken {
    fileprivate let source: CancellationTokenSource? // no-op when `nil`

    /// Returns `true` if cancellation has been requested for this token.
    public var isCancelling: Bool {
        return source?.isCancelling ?? false
    }

    /// Registers the closure that will be called when the token is canceled.
    /// If this token is already cancelled, the closure will be run immediately
    /// and synchronously.
    public func register(_ closure: @escaping () -> Void) {
        source?.register(closure)
    }

    /// Special no-op token which does nothing.
    internal static var noOp: CancellationToken {
        return CancellationToken(source: nil)
    }
}

// MARK: - Result

/// An enum representing either a success with a result value, or a failure.
@available(*, deprecated, message: "Nuke no longer exposes public `Result` type, it's only used privately.")
public enum Result<T> {
    case success(T), failure(Error)

    /// Returns a `value` if the result is success.
    public var value: T? {
        if case let .success(val) = self { return val } else { return nil }
    }

    /// Returns an `error` if the result is failure.
    public var error: Error? {
        if case let .failure(err) = self { return err } else { return nil }
    }
}

// MARK: - Processing

@available(*, deprecated, message: "Please use new `ImageProcessing` protocol instead.")
public protocol Processing: Equatable {
    func process(_ image: Image) -> Image?
}

@available(*, deprecated, message: "Please use `ImageRequest` methods which append image processors If you'd like to continue using `ProcessorComposition` please copy it in your project.")
public struct ProcessorComposition: Processing {
    private let processors: [AnyProcessor]

    public init(_ processors: [AnyProcessor]) {
        self.processors = processors
    }

    public func process(_ input: Image) -> Image? {
        return processors.reduce(input) { image, processor in
            return autoreleasepool { image.flatMap(processor.process) }
        }
    }

    public static func ==(lhs: ProcessorComposition, rhs: ProcessorComposition) -> Bool {
        return lhs.processors == rhs.processors
    }
}

@available(*, deprecated, message: "Please use `AnyImageProcessor` instead.")
public struct AnyProcessor: Processing {
    private let _process: (Image) -> Image?
    private let _processor: Any
    private let _equals: (AnyProcessor) -> Bool

    public init<P: Processing>(_ processor: P) {
        self._process = { processor.process($0) }
        self._processor = processor
        self._equals = { ($0._processor as? P) == processor }
    }

    public func process(_ image: Image) -> Image? {
        return self._process(image)
    }

    public static func ==(lhs: AnyProcessor, rhs: AnyProcessor) -> Bool {
        return lhs._equals(rhs)
    }
}

#if !os(macOS)
import UIKit

@available(*, deprecated, message: "Please use `ImageDecompressor` instead.")
public struct Decompressor: Processing {
    public enum ContentMode {
        case aspectFill
        case aspectFit
    }

    public static let MaximumSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

    private let targetSize: CGSize
    private let contentMode: ContentMode

    public init(targetSize: CGSize = MaximumSize, contentMode: ContentMode = .aspectFill) {
        self.targetSize = targetSize
        self.contentMode = contentMode
    }

    private func _map(mode: ContentMode) -> ImageDecompressor.ContentMode {
        switch mode {
        case .aspectFill: return .aspectFill
        case .aspectFit: return .aspectFit
        }
    }

    public func process(_ image: Image) -> Image? {
        return decompress(image, targetSize: targetSize, contentMode: _map(mode: contentMode))
    }

    public static func ==(lhs: Decompressor, rhs: Decompressor) -> Bool {
        return lhs.targetSize == rhs.targetSize && lhs.contentMode == rhs.contentMode
    }

    #if !os(watchOS)
    public static func targetSize(for view: UIView) -> CGSize { // in pixels
        return ImageDecompressor.targetSize(for: view)
    }
    #endif
}
#endif

@available(*, deprecated, message: "Please use new `ImageProcessing` protocol instead")
private struct _ImageProcessorBridge: ImageProcessing { // Bridge from Processing to ImageProcessing
    let processor: AnyProcessor

    func process(image: Image, context: ImageProcessingContext) -> Image? {
        return processor.process(image)
    }

    static func ==(lhs: _ImageProcessorBridge, rhs: _ImageProcessorBridge) -> Bool {
        return lhs.processor == rhs.processor
    }
}

public extension ImageRequest {
    @available(*, deprecated, message: "Please use new functions that works with `ImageProcessing` instead.")
    public mutating func process<P: Processing>(with processor: P) {
        let bridge = _ImageProcessorBridge(processor: AnyProcessor(processor))
        guard let existing = self.processor else {
            self.processor = AnyImageProcessor(bridge)
            return
        }
        // Chain new processor and the existing one.
        self.processor = AnyImageProcessor(ImageProcessorComposition([existing, AnyImageProcessor(bridge)]))
    }

    @available(*, deprecated, message: "Please use new functions that works with `ImageProcessing` instead.")
    public func processed<P: Processing>(with processor: P) -> ImageRequest {
        var request = self
        request.process(with: processor)
        return request
    }
}

public extension ImageRequest.MemoryCacheOptions {
    @available(*, deprecated, message: "Renamed to `isReadAllowed`.")
    public var readAllowed: Bool {
        get { return isReadAllowed }
        set { isReadAllowed = newValue }
    }
    
    @available(*, deprecated, message: "Renamed to `isWriteAllowed`.")
    public var writeAllowed: Bool {
        get { return isWriteAllowed }
        set { isWriteAllowed = newValue }
    }
}

// MARK: - Preheater

@available(*, deprecated, message: "Please use `ImagePreheater` instead.")
public final class Preheater {
    private let manager: Manager
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Preheater")
    private let preheatQueue = OperationQueue()
    private var tasks = [AnyHashable: Task]()

    public init(manager: Manager = Manager.shared, maxConcurrentRequestCount: Int = 2) {
        self.manager = manager
        self.preheatQueue.maxConcurrentOperationCount = maxConcurrentRequestCount
    }

    public func startPreheating(with requests: [Request]) {
        queue.async {
            requests.forEach(self._startPreheating)
        }
    }

    private func _startPreheating(with request: Request) {
        let key = ImageRequest.LoadKey(request: request)
        guard tasks[key] == nil else { return } // already exists

        let task = Task(request: request, key: key)
        let token = task.cts.token

        let operation = Operation(starter: { [weak self] finish in
            self?.manager.loadImage(with: request, token: token) { _ in
                self?._remove(task)
                finish()
            }
            token.register(finish)
        })
        preheatQueue.addOperation(operation)
        token.register { [weak operation] in operation?.cancel() }

        tasks[key] = task
    }

    private func _remove(_ task: Task) {
        queue.async {
            guard self.tasks[task.key] === task else { return }
            self.tasks[task.key] = nil
        }
    }

    public func stopPreheating(with requests: [Request]) {
        queue.async {
            requests.forEach(self._stopPreheating)
        }
    }

    private func _stopPreheating(with request: Request) {
        if let task = tasks[ImageRequest.LoadKey(request: request)] {
            tasks[task.key] = nil
            task.cts.cancel()
        }
    }

    /// Stops all preheating tasks.
    public func stopPreheating() {
        queue.async {
            self.tasks.forEach { $0.1.cts.cancel() }
            self.tasks.removeAll()
        }
    }

    private final class Task {
        let key: AnyHashable
        let request: Request
        let cts = CancellationTokenSource()

        init(request: Request, key: AnyHashable) {
            self.request = request
            self.key = key
        }
    }
}
