// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import CoreGraphics

public extension ImagePipeline.Configuration {
    /// - warning: Soft-deprecated in 9.0. The default image decoder now
    /// automatically attaches image data to the newly added ImageContainer type.
    /// To learn how to implement animated image support using this new type,
    /// see the new Image Formats guide https://github.com/kean/Nuke/blob/9.3.0/Documentation/Guides/image-formats.md"
    static var isAnimatedImageDataEnabled: Bool {
        get { _isAnimatedImageDataEnabled }
        set { _isAnimatedImageDataEnabled = newValue }
    }
}

private var _animatedImageDataAK = "Nuke.AnimatedImageData.AssociatedKey"

extension PlatformImage {
    /// - warning: Soft-deprecated in Nuke 9.0.
    public var animatedImageData: Data? {
        get { _animatedImageData }
        set { _animatedImageData = newValue }
    }

    // Deprecated in 9.0
    internal var _animatedImageData: Data? {
        get { objc_getAssociatedObject(self, &_animatedImageDataAK) as? Data }
        set { objc_setAssociatedObject(self, &_animatedImageDataAK, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

public extension DataCaching {
    // Deprecated in 9.2
    @available(*, deprecated, message: "This method exists for backward-compatibility with Nuke 9.1.x and lower.")
    func removeData(for key: String) {}
}

public extension DataCache {
    // Deprecated in 9.3.1
    @available(*, deprecated, message: "Count limit is deprecated and will be removed in the next major release")
    var countLimit: Int {
        get { deprecatedCountLimit }
        set { deprecatedCountLimit = newValue }
    }
}

public extension ImageTask {
    // Deprecated in 9.4.0
    @available(*, deprecated, message: "Please use the closure type directly")
    typealias Completion = ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)

    // Deprecated in 9.4.0
    @available(*, deprecated, message: "Please use the closure type directly")
    typealias ProgressHandler = (_ intermediateResponse: ImageResponse?, _ completedUnitCount: Int64, _ totalUnitCount: Int64) -> Void
}

// Deprecated in 9.4.1
@available(*, deprecated, message: "Renamed to ImagePrefetcher")
public typealias ImagePreheater = ImagePrefetcher

public extension ImagePrefetcher {
    // Deprecated in 9.4.1
    @available(*, deprecated, message: "Renamed to startPrefetching")
    func startPreheating(with urls: [URL]) {
        startPrefetching(with: urls)
    }

    // Deprecated in 9.4.1
    @available(*, deprecated, message: "Renamed to startPrefetching")
    func startPreheating(with requests: [ImageRequest]) {
        startPrefetching(with: requests)
    }

    // Deprecated in 9.4.1
    @available(*, deprecated, message: "Renamed to stopPrefetching")
    func stopPreheating(with urls: [URL]) {
        stopPrefetching(with: urls)
    }

    // Deprecated in 9.4.1
    @available(*, deprecated, message: "Renamed to stopPrefetching")
    func stopPreheating(with requests: [ImageRequest]) {
        stopPrefetching(with: requests)
    }

    // Deprecated in 9.4.1
    @available(*, deprecated, message: "Renamed to stopPrefetching")
    func stopPreheating() {
        stopPrefetching()
    }
}

public extension ImagePipeline {
    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Use pipeline.cache[url] instead")
    func cachedImage(for url: URL) -> ImageContainer? {
        cachedImage(for: ImageRequest(url: url))
    }

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Use pipeline.cache[request] instead")
    func cachedImage(for request: ImageRequest) -> ImageContainer? {
        cache[request]
    }

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "If needed, use pipeline.cache.makeDataCacheKey(for:) instead. For original image data, remove the processors from the request. In general, there should be no need to create the keys manually anymore.")
    func cacheKey(for request: ImageRequest, item: DataCacheItem) -> String {
        switch item {
        case .originalImageData:
            var request = request
            request.processors = []
            return request.makeDataCacheKey()
        case .finalImage: return request.makeDataCacheKey()
        }
    }

    @available(*, deprecated, message: "Please use `dataCachePolicy` instead. The recommended policy is the new `.automatic` policy.")
    enum DataCacheItem {
        /// Same as the new `DataCachePolicy.storeOriginalImageData`
        case originalImageData
        /// Same as the new `DataCachePolicy.storeEncodedImages`
        case finalImage
    }
}

// Deprecated in 10.0.0
@available(*, deprecated, message: "Please use ImagePipelineDelegate")
public protocol ImagePipelineObserving {
    /// Delivers the events produced by the image tasks started via `loadImage` method.
    func pipeline(_ pipeline: ImagePipeline, imageTask: ImageTask, didReceiveEvent event: ImageTaskEvent)
}

public extension ImageRequestOptions {
    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please use `ImagePipeline.Delegate` instead. This API does nothing starting with Nuke 10.")
    var cacheKey: AnyHashable? {
        get { nil }
        set { debugPrint("The ImageRequestOptions.cacheKey API does nothing starting with Nuke 10") } // swiftlint:disable:this unused_setter_value
    }

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "This API does nothing starting with Nuke 10. If you found an issue in coalescing, please report it on GitHub and consider disabling it using ImagePipeline.Configuration.")
    var loadKey: AnyHashable? {
        get { nil }
        set { debugPrint("The ImageRequestOptions.loadKey API does nothing starting with Nuke 10") } // swiftlint:disable:this unused_setter_value
    }

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please pass imageId (`ImageRequest.UserInfoKey.imageId`) in the request `userInfo`. The deprecated API does nothing starting with Nuke 10.")
    var filteredURL: AnyHashable? {
        get { nil }
        set { debugPrint("The ImageRequestOptions.filteredURL API does nothing starting with Nuke 10") } // swiftlint:disable:this unused_setter_value
    }

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "ImageRequestOptions are deprecated")
    init(memoryCacheOptions: MemoryCacheOptions = .init(),
         filteredURL: String? = nil,
         cacheKey: AnyHashable? = nil,
         loadKey: AnyHashable? = nil,
         userInfo: [AnyHashable: Any] = [:]) {
        self.init()
        self.memoryCacheOptions = memoryCacheOptions
        self.cacheKey = cacheKey
        self.loadKey = loadKey
        self.filteredURL = filteredURL
    }
}

public extension ImagePipeline.Configuration {
    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Renamed to isTaskCoalescingEnabled")
    var isDeduplicationEnabled: Bool {
        get { isTaskCoalescingEnabled }
        set { isTaskCoalescingEnabled = newValue }
    }
}
