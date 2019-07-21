// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageRequest (Deprecated)

extension ImageRequest {

    @available(*, deprecated, message: "Please use `var processors: [ImageProcessing]` instead")
    public var processor: ImageProcessing? {
        get { return processors.first }
        set {
            guard let newValue = newValue else {
                processors = []
                return
            }
            processors = [newValue]
        }
    }

    @available(*, deprecated, message: "Please use `ImageRequestOptions` instead, it now contains all the advanced options")
    public var memoryCacheOptions: ImageRequestOptions.MemoryCacheOptions {
        get { return options.memoryCacheOptions }
        set { options.memoryCacheOptions = newValue }
    }

    @available(*, deprecated, message: "Please use `ImageRequestOptions` instead, it now contains all the advanced options")
    public var cacheKey: AnyHashable? {
        get { return options.cacheKey }
        set { options.cacheKey = newValue }
    }

    @available(*, deprecated, message: "Please use `ImageRequestOptions` instead, it now contains all the advanced options")
    public var loadKey: AnyHashable? {
        get { return options.loadKey }
        set { options.loadKey = newValue }
    }

    @available(*, deprecated, message: "Please use `ImageRequestOptions` instead, it now contains all the advanced options")
    public var userInfo: Any? {
        get { return options.userInfo }
        set { options.userInfo = newValue }
    }

    @available(*, deprecated, message: "Please use the new unified initializer `ImageRequest.init(url:processors:priority:options:)` instead")
    public init(url: URL, processor: ImageProcessing) {
        self = ImageRequest(url: url, processors: [processor])
    }

    @available(*, deprecated, message: "Please use the new unified initializer `ImageRequest.init(urlRequest:processors:priority:options:)` instead")
    public init(urlRequest: URLRequest, processor: ImageProcessing) {
        self = ImageRequest(urlRequest: urlRequest, processors: [processor])
    }
}

extension ImageRequest {

    @available(*, deprecated, message: "Please use the new unified initializer `ImageRequest.init(urlRequest:processors:priority:options:)` instead or set processors via new `var processors: [ImageProcessing]` property.")
    public mutating func process(with processor: ImageProcessing) {
        processors.append(processor)
    }

    @available(*, deprecated, message: "Please use the new unified initializer `ImageRequest.init(urlRequest:processors:priority:options:)` instead or set processors via new `var processors: [ImageProcessing]` property.")
    public func processed(with processor: ImageProcessing) -> ImageRequest {
        var request = self
        request.process(with: processor)
        return request
    }

    @available(*, deprecated, message: "Please use `ImageProcessor.Anonymous` instead. Key must also be a `String` now")
    public mutating func process(key: String, _ closure: @escaping (Image) -> Image?) {
        process(with: ImageProcessor.Anonymous(id: key, closure))
    }

    @available(*, deprecated, message: "Please use `ImageProcessor.Anonymous` instead. Key must also be a `String` now")
    public func processed(key: String, _ closure: @escaping (Image) -> Image?) -> ImageRequest {
        return processed(with: ImageProcessor.Anonymous(id: key, closure))
    }
}

#if !os(macOS)
import UIKit

extension ImageRequest {
    @available(*, deprecated, message: "Please use the new unified initializer `ImageRequest.init(url:processors:priority:options:)` with `ImageProcessor.Resize` instead. Target size for `ImageProcessor.Resize` is in points by default, not pixels! For more info see https://github.com/kean/Nuke/pull/229.")
    public init(url: URL, targetSize: CGSize, contentMode: ImageDecompressor.ContentMode, upscale: Bool = false) {
        self.init(url: url, processor: ImageDecompressor(targetSize: targetSize, contentMode: contentMode, upscale: upscale))
    }

    @available(*, deprecated, message: "Please use the new unified initializer `ImageRequest.init(urlRequest:processors:priority:options:)` with `ImageProcessor.Resize`instead. Target size for `ImageProcessor.Resize` is in points by default, not pixels! For more info see https://github.com/kean/Nuke/pull/229.")
    public init(urlRequest: URLRequest, targetSize: CGSize, contentMode: ImageDecompressor.ContentMode, upscale: Bool = false) {
        self.init(urlRequest: urlRequest, processor: ImageDecompressor(targetSize: targetSize, contentMode: contentMode, upscale: upscale))
    }
}
#endif

// MARK: - ImageDecompressor (Deprecated)

#if !os(macOS)
import UIKit

/// Decompresses and (optionally) scales down input images. Maintains
/// original aspect ratio.
///
/// Decompressing compressed image formats (such as JPEG) can significantly
/// improve drawing performance as it allows a bitmap representation to be
/// created in a background rather than on the main thread.
@available(*, deprecated, message: "Decompression now runs automatically after all processors were applied and only if still needed. To disable decompression use `ImagePipeline.Configuration.isDecompressionEnabled`. If you were using `ImageDecompressor` to resize image please use `ImageProcessor.Resize`. Please be aware that the target size for `ImageProcessor.Resize` is in points by default, not pixels like in `ImageDecompressor`! For more info see https://github.com/kean/Nuke/pull/229.")
public struct ImageDecompressor: ImageProcessing {
    public var identifier: String {
        return resize.identifier
    }

    public var hashableIdentifier: AnyHashable {
        return resize.hashableIdentifier
    }

    /// An option for how to resize the image.
    public enum ContentMode {
        /// Scales the image so that it completely fills the target size.
        /// Doesn't clip images.
        case aspectFill

        /// Scales the image so that it fits the target size.
        case aspectFit
    }

    /// Size to pass to disable resizing.
    public static let MaximumSize = CGSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
    )

    private let resize: ImageProcessor.Resize

    /// Initializes `Decompressor` with the given parameters.
    /// - parameter targetSize: Size in pixels. `MaximumSize` by default.
    /// - parameter contentMode: An option for how to resize the image
    /// to the target size. `.aspectFill` by default.
    public init(targetSize: CGSize = MaximumSize, contentMode: ContentMode = .aspectFill, upscale: Bool = false) {
        self.resize = ImageProcessor.Resize(size: targetSize, unit: .pixels, contentMode: .init(contentMode), upscale: upscale)
    }

    public func process(image: Image, context: ImageProcessingContext?) -> Image? {
        return resize.process(image: image, context: context)
    }

    /// Returns true if both have the same `targetSize` and `contentMode`.
    public static func == (lhs: ImageDecompressor, rhs: ImageDecompressor) -> Bool {
        return lhs.resize == rhs.resize
    }

    #if !os(watchOS)
    /// Returns target size in pixels for the given view. Takes main screen
    /// scale into the account.
    public static func targetSize(for view: UIView) -> CGSize { // in pixels
        let scale = UIScreen.main.scale
        let size = view.bounds.size
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
    #endif
}

@available(*, deprecated)
extension ImageProcessor.Resize.ContentMode {
    init(_ contentMode: ImageDecompressor.ContentMode) {
        switch contentMode {
        case .aspectFill: self = .aspectFill
        case .aspectFit: self = .aspectFit
        }
    }
}

#endif

// MARK: - AnyImageProcessor (Deprecated)

@available(*, deprecated, message: "The new `ImageProcessing` protocol now longer has Self requirement which were previously needed due to `Equatable`, `AnyImageProcessor` is no longer needed")
public struct AnyImageProcessor {}

// MARK: - ImageTaskMetrics (Deprecated)

extension ImagePipeline {
    @available(*, deprecated, message: "Please use os_signposts instead. For more info see `ImagePipeline.Configuration.isSignpostLoggingEnabled`")
    public var didFinishCollectingMetrics: ((ImageTask, ImageTaskMetrics) -> Void)? {
        set {} // swiftlint:disable:this unused_setter_value
        get { return nil }
    }
}

@available(*, deprecated, message: "Please use os_signposts instead. For more info see `ImagePipeline.Configuration.isSignpostLoggingEnabled`")
public struct ImageTaskMetrics: CustomDebugStringConvertible {
    public let taskId: Int
    public internal(set) var wasCancelled: Bool = false
    public internal(set) var session: SessionMetrics?

    public let startDate: Date
    public internal(set) var processStartDate: Date?
    public internal(set) var processEndDate: Date?
    public internal(set) var endDate: Date? // failed or completed
    public var totalDuration: TimeInterval? {
        guard let endDate = endDate else { return nil }
        return endDate.timeIntervalSince(startDate)
    }

    /// Returns `true` is the task wasn't the one that initiated image loading.
    public internal(set) var wasSubscibedToExistingSession: Bool = false
    public internal(set) var isMemoryCacheHit: Bool = false

    init(taskId: Int, startDate: Date) {
        self.taskId = taskId; self.startDate = startDate
    }

    public var debugDescription: String {
        return "Deprecated, please use os_signposts instead. For more info see `ImagePipeline.Configuration.isSignpostLoggingEnabled`"
    }

    public final class SessionMetrics: CustomDebugStringConvertible {
        public let sessionId: Int
        public internal(set) var wasCancelled: Bool = false
        public let startDate = Date()

        public internal(set) var checkDiskCacheStartDate: Date?
        public internal(set) var checkDiskCacheEndDate: Date?

        public internal(set) var loadDataStartDate: Date?
        public internal(set) var loadDataEndDate: Date?

        public internal(set) var decodeStartDate: Date?
        public internal(set) var decodeEndDate: Date?

        @available(*, deprecated, message: "Please use the same property on `ImageTaskMetrics` instead.")
        public internal(set) var processStartDate: Date?

        @available(*, deprecated, message: "Please use the same property on `ImageTaskMetrics` instead.")
        public internal(set) var processEndDate: Date?

        public internal(set) var endDate: Date? // failed or completed
        public var totalDuration: TimeInterval? {
            guard let endDate = endDate else { return nil }
            return endDate.timeIntervalSince(startDate)
        }

        public internal(set) var wasResumed: Bool?
        public internal(set) var resumedDataCount: Int?
        public internal(set) var serverConfirmedResume: Bool?

        public internal(set) var downloadedDataCount: Int?
        public var totalDownloadedDataCount: Int? {
            guard let downloaded = self.downloadedDataCount else { return nil }
            return downloaded + (resumedDataCount ?? 0)
        }

        init(sessionId: Int) { self.sessionId = sessionId }

        public var debugDescription: String {
            return "Deprecated, please use os_signposts instead. For more info see `ImagePipeline.Configuration.isSignpostLoggingEnabled`"
        }
    }
}

// MARK: - ImageTask (Deprecated)

extension ImageTask {
    @available(*, deprecated, message: "Please use `var priority: ImageRequest.Priority`")
    public func setPriority(_ priority: ImageRequest.Priority) {
        self.priority = priority
    }
}
