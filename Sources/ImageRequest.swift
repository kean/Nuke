// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

#if !os(macOS)
import UIKit
#endif

/// Represents an image request.
public struct ImageRequest {

    // MARK: Parameters of the Request

    var urlString: String? {
        return ref.urlString
    }

    /// The `URLRequest` used for loading an image.
    public var urlRequest: URLRequest {
        get { return ref.resource.urlRequest }
        set {
            mutate {
                $0.resource = Resource.urlRequest(newValue)
                $0.urlString = newValue.url?.absoluteString
            }
        }
    }

    /// Processor to be applied to the image. `Decompressor` by default.
    ///
    /// Decompressing compressed image formats (such as JPEG) can significantly
    /// improve drawing performance as it allows a bitmap representation to be
    /// created in a background rather than on the main thread.
    public var processor: AnyImageProcessor? {
        get {
            // Default processor on macOS is nil, on other platforms is Decompressor
            #if !os(macOS)
            return ref.isDefaultProcessorUsed ? ImageRequest.decompressor : ref.processor
            #else
            return ref.isDefaultProcessorUsed ? nil : ref.processor
            #endif
        }
        set {
            mutate {
                $0.isDefaultProcessorUsed = false
                $0.processor = newValue
            }
        }
    }

    /// The policy to use when reading or writing images to the memory cache.
    public struct MemoryCacheOptions {
        /// `true` by default.
        public var isReadAllowed = true

        /// `true` by default.
        public var isWriteAllowed = true

        public init() {}
    }

    /// `MemoryCacheOptions()` (read allowed, write allowed) by default.
    public var memoryCacheOptions: MemoryCacheOptions {
        get { return ref.memoryCacheOptions }
        set { mutate { $0.memoryCacheOptions = newValue } }
    }

    /// The execution priority of the request.
    public enum Priority: Int, Comparable {
        case veryLow = 0, low, normal, high, veryHigh

        var queuePriority: Operation.QueuePriority {
            switch self {
            case .veryLow: return .veryLow
            case .low: return .low
            case .normal: return .normal
            case .high: return .high
            case .veryHigh: return .veryHigh
            }
        }

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    /// The relative priority of the operation. This value is used to influence
    /// the order in which requests are executed. `.normal` by default.
    public var priority: Priority {
        get { return ref.priority }
        set { mutate { $0.priority = newValue } }
    }

    /// Returns a key that compares requests with regards to caching images.
    ///
    /// The default key considers two requests equivalent it they have the same
    /// `URLRequests` and the same processors. `URLRequests` are compared
    /// just by their `URLs`.
    public var cacheKey: AnyHashable? {
        get { return ref.cacheKey }
        set { mutate { $0.cacheKey = newValue } }
    }

    /// Returns a key that compares requests with regards to loading images.
    ///
    /// The default key considers two requests equivalent it they have the same
    /// `URLRequests` and the same processors. `URLRequests` are compared by
    /// their `URL`, `cachePolicy`, and `allowsCellularAccess` properties.
    public var loadKey: AnyHashable? {
        get { return ref.loadKey }
        set { mutate { $0.loadKey = newValue } }
    }

    /// If decoding is disabled, when the image data is loaded, the pipeline is
    /// not going to create an image from it and will produce the `.decodingFailed`
    /// error instead. `false` by default.
    var isDecodingDisabled: Bool {
        // This only used by `ImagePreheater` right now
        get { return ref.isDecodingDisabled }
        set { mutate { $0.isDecodingDisabled = newValue } }
    }

    /// Custom info passed alongside the request.
    public var userInfo: Any? {
        get { return ref.userInfo }
        set { mutate { $0.userInfo = newValue } }
    }

    // MARK: Initializers

    /// Initializes a request with the given URL.
    public init(url: URL) {
        ref = Container(resource: Resource.url(url))
        ref.urlString = url.absoluteString
        // creating `.absoluteString` takes 50% of time of Request creation,
        // it's still faster than using URLs as cache keys
    }

    /// Initializes a request with the given request.
    public init(urlRequest: URLRequest) {
        ref = Container(resource: Resource.urlRequest(urlRequest))
        ref.urlString = urlRequest.url?.absoluteString
    }

    #if !os(macOS)

    /// Initializes a request with the given URL.
    /// - parameter processor: Custom image processer.
    public init<Processor: ImageProcessing>(url: URL, processor: Processor) {
        self.init(url: url)
        self.processor = AnyImageProcessor(processor)
    }

    /// Initializes a request with the given request.
    /// - parameter processor: Custom image processer.
    public init<Processor: ImageProcessing>(urlRequest: URLRequest, processor: Processor) {
        self.init(urlRequest: urlRequest)
        self.processor = AnyImageProcessor(processor)
    }

    /// Initializes a request with the given URL.
    /// - parameter targetSize: Size in pixels.
    /// - parameter contentMode: An option for how to resize the image
    /// to the target size.
    public init(url: URL, targetSize: CGSize, contentMode: ImageDecompressor.ContentMode, upscale: Bool = false) {
        self.init(url: url, processor: ImageDecompressor(targetSize: targetSize, contentMode: contentMode, upscale: upscale))
    }

    /// Initializes a request with the given request.
    /// - parameter targetSize: Size in pixels.
    /// - parameter contentMode: An option for how to resize the image
    /// to the target size.
    public init(urlRequest: URLRequest, targetSize: CGSize, contentMode: ImageDecompressor.ContentMode, upscale: Bool = false) {
        self.init(urlRequest: urlRequest, processor: ImageDecompressor(targetSize: targetSize, contentMode: contentMode, upscale: upscale))
    }

    private static let decompressor = AnyImageProcessor(ImageDecompressor())

    #endif

    // CoW:

    private var ref: Container

    private mutating func mutate(_ closure: (Container) -> Void) {
        if !isKnownUniquelyReferenced(&ref) {
            ref = Container(container: ref)
        }
        closure(ref)
    }

    /// Just like many Swift built-in types, `ImageRequest` uses CoW approach to
    /// avoid memberwise retain/releases when `ImageRequest` is passed around.
    private class Container {
        var resource: Resource
        var urlString: String? // memoized absoluteString
        // true unless user set a custom one, this allows us not to store the
        // default processor anywhere in the `Container` & skip equality tests
        // when the default processor is used
        var isDefaultProcessorUsed: Bool = true
        var processor: AnyImageProcessor?
        var memoryCacheOptions = MemoryCacheOptions()
        var priority: ImageRequest.Priority = .normal
        var cacheKey: AnyHashable?
        var loadKey: AnyHashable?
        var isDecodingDisabled: Bool = false
        var userInfo: Any?

        /// Creates a resource with a default processor.
        init(resource: Resource) {
            self.resource = resource
        }

        /// Creates a copy.
        init(container ref: Container) {
            self.resource = ref.resource
            self.urlString = ref.urlString
            self.isDefaultProcessorUsed = ref.isDefaultProcessorUsed
            self.processor = ref.processor
            self.memoryCacheOptions = ref.memoryCacheOptions
            self.priority = ref.priority
            self.cacheKey = ref.cacheKey
            self.loadKey = ref.loadKey
            self.isDecodingDisabled = ref.isDecodingDisabled
            self.userInfo = ref.userInfo
        }
    }

    /// Resource representation (either URL or URLRequest).
    private enum Resource {
        case url(URL)
        case urlRequest(URLRequest)

        var urlRequest: URLRequest {
            switch self {
            case let .url(url): return URLRequest(url: url) // create lazily
            case let .urlRequest(urlRequest): return urlRequest
            }
        }
    }
}

public extension ImageRequest {
    /// Appends a processor to the request. You can append arbitrary number of
    /// processors to the request.
    mutating func process<P: ImageProcessing>(with processor: P) {
        guard let existing = self.processor else {
            self.processor = AnyImageProcessor(processor)
            return
        }
        // Chain new processor and the existing one.
        self.processor = AnyImageProcessor(ImageProcessorComposition([existing, AnyImageProcessor(processor)]))
    }

    /// Appends a processor to the request. You can append arbitrary number of
    /// processors to the request.
    func processed<P: ImageProcessing>(with processor: P) -> ImageRequest {
        var request = self
        request.process(with: processor)
        return request
    }

    /// Appends a processor to the request. You can append arbitrary number of
    /// processors to the request.
    mutating func process<Key: Hashable>(key: Key, _ closure: @escaping (Image) -> Image?) {
        process(with: AnonymousImageProcessor<Key>(key, closure))
    }

    /// Appends a processor to the request. You can append arbitrary number of
    /// processors to the request.
    func processed<Key: Hashable>(key: Key, _ closure: @escaping (Image) -> Image?) -> ImageRequest {
        return processed(with: AnonymousImageProcessor<Key>(key, closure))
    }
}

extension ImageRequest {
    struct CacheKey: Hashable {
        let request: ImageRequest

        func hash(into hasher: inout Hasher) {
            if let customKey = request.ref.cacheKey {
                hasher.combine(customKey)
            } else {
                hasher.combine(request.ref.urlString?.hashValue ?? 0)
            }
        }

        static func == (lhs: CacheKey, rhs: CacheKey) -> Bool {
            let lhs = lhs.request, rhs = rhs.request
            if let lhsCustomKey = lhs.ref.cacheKey, let rhsCustomKey = rhs.ref.cacheKey {
                return lhsCustomKey == rhsCustomKey
            }
            guard lhs.ref.urlString == rhs.ref.urlString else {
                return false
            }
            return (lhs.ref.isDefaultProcessorUsed && rhs.ref.isDefaultProcessorUsed)
                || (lhs.processor == rhs.processor)
        }
    }

    struct LoadKey: Hashable {
        let request: ImageRequest

        func hash(into hasher: inout Hasher) {
            if let customKey = request.ref.loadKey {
                hasher.combine(customKey)
            } else {
                hasher.combine(request.ref.urlString?.hashValue ?? 0)
            }
        }

        static func == (lhs: LoadKey, rhs: LoadKey) -> Bool {
            func isEqual(_ lhs: URLRequest, _ rhs: URLRequest) -> Bool {
                return lhs.cachePolicy == rhs.cachePolicy
                    && lhs.allowsCellularAccess == rhs.allowsCellularAccess
            }
            let lhs = lhs.request, rhs = rhs.request
            if let lhsCustomKey = lhs.ref.loadKey, let rhsCustomKey = rhs.ref.loadKey {
                return lhsCustomKey == rhsCustomKey
            }
            return lhs.ref.urlString == rhs.ref.urlString
                && isEqual(lhs.urlRequest, rhs.urlRequest)
        }
    }
}
