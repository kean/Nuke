// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

// Deprecated in Nuke 11.0
@available(*, deprecated, message: "Please use ImageDecodingRegistry directly.")
public protocol ImageDecoderRegistering: ImageDecoding {
    /// Returns non-nil if the decoder can be used to decode the given data.
    ///
    /// - parameter data: The same data is going to be delivered to decoder via
    /// `decode(_:)` method. The same instance of the decoder is going to be used.
    init?(data: Data, context: ImageDecodingContext)

    /// Returns non-nil if the decoder can be used to progressively decode the
    /// given partially downloaded data.
    ///
    /// - parameter data: The first and the next data chunks are going to be
    /// delivered to the decoder via `decodePartiallyDownloadedData(_:)` method.
    init?(partiallyDownloadedData data: Data, context: ImageDecodingContext)
}

// Deprecated in Nuke 11.0
@available(*, deprecated, message: "Please use ImageDecodingRegistry directly.")
extension ImageDecoderRegistering {
    /// The default implementation which simply returns `nil` (no progressive
    /// decoding available).
    public init?(partiallyDownloadedData data: Data, context: ImageDecodingContext) {
        return nil
    }
}

extension ImageDecoderRegistry {
    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Please use register method that accepts a closure.")
    public func register<Decoder: ImageDecoderRegistering>(_ decoder: Decoder.Type) {
        register { context in
            if context.isCompleted {
                return decoder.init(data: context.data, context: context)
            } else {
                return decoder.init(partiallyDownloadedData: context.data, context: context)
            }
        }
    }
}

extension ImageProcessingContext {
    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Please use `isCompleted` instead.")
    public var isFinal: Bool {
        isCompleted
    }
}

extension ImageContainer {
    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Please create a copy of and modify it instead or define a similar helper method yourself.")
    public func map(_ closure: (PlatformImage) -> PlatformImage?) -> ImageContainer? {
        guard let image = closure(self.image) else { return nil }
        return ImageContainer(image: image, type: type, isPreview: isPreview, data: data, userInfo: userInfo)
    }
}

extension ImageTask {
    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Please use setPriority(_:) method.")
    public var priority: ImageRequest.Priority {
        get { _priority }
        set { setPriority(newValue) }
    }

    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Please use progress.completed instead.")
    public var completedUnitCount: Int64 { progress.completed }

    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Please use progress.total instead.")
    public var totalUnitCount: Int64 { progress.total }
}

extension DataCache {
    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Please use String directly instead.")
    public typealias Key = String
}

extension ImageCaching {
    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Please use ImagePipeline.Cache that goes through ImagePipelineDelegate instead.")
    public subscript(request: any ImageRequestConvertible) -> ImageContainer? {
        get { self[ImageCacheKey(request: request.asImageRequest())] }
        set { self[ImageCacheKey(request: request.asImageRequest())] = newValue }
    }
}

extension ImageProcessing where Self == ImageProcessors.Anonymous {
    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Renamed to `custom(id:_:)`.")
    public static func process(id: String, _ closure: @Sendable @escaping (PlatformImage) -> PlatformImage?) -> ImageProcessors.Anonymous {
        ImageProcessors.Anonymous(id: id, closure)
    }
}

extension ImagePipeline.Cache {
    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Please use variants that accept URL or ImageRequest.")
    public subscript(request: any ImageRequestConvertible) -> ImageContainer? {
        get { self[request.asImageRequest()] }
        nonmutating set { self[request.asImageRequest()] = newValue }
    }

    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Please use variants that accept URL or ImageRequest.")
    public func cachedImage(for request: any ImageRequestConvertible, caches: Caches = [.all]) -> ImageContainer? {
        cachedImage(for: request.asImageRequest(), caches: caches)
    }
}
