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

extension ImagePipeline.Configuration {
    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Please use `ImagePipeline.DataCachePolicy`")
    public typealias DataCachePolicy = ImagePipeline.DataCachePolicy
}

/// Deprecated in Nuke 11.6. (Soft-deprecated in Nuke 11.0).
@available(*, deprecated, message: "Please use ImageRequest or URL directrly`")
public protocol ImageRequestConvertible {
    /// Returns a request.
    func asImageRequest() -> ImageRequest
}

@available(*, deprecated, message: "Please use ImageRequest or URL directrly`")
extension ImageRequest: ImageRequestConvertible {
    public func asImageRequest() -> ImageRequest { self }
}

@available(*, deprecated, message: "Please use ImageRequest or URL directrly`")
extension URL: ImageRequestConvertible {
    public func asImageRequest() -> ImageRequest { ImageRequest(url: self) }
}

@available(*, deprecated, message: "Please use ImageRequest or URL directrly`")
extension Optional: ImageRequestConvertible where Wrapped == URL {
    public func asImageRequest() -> ImageRequest { ImageRequest(url: self) }
}

@available(*, deprecated, message: "Please use ImageRequest or URL directrly`")
extension URLRequest: ImageRequestConvertible {
    public func asImageRequest() -> ImageRequest { ImageRequest(urlRequest: self) }
}

@available(*, deprecated, message: "Please use ImageRequest or URL directrly`")
extension String: ImageRequestConvertible {
    public func asImageRequest() -> ImageRequest { ImageRequest(url: URL(string: self)) }
}

// Deprecated in Nuke 11.1
@available(*, deprecated, message: "Please use `DataLoader/delegate` instead")
public protocol DataLoaderObserving {
    func dataLoader(_ loader: DataLoader, urlSession: URLSession, dataTask: URLSessionDataTask, didReceiveEvent event: DataTaskEvent)

    /// Sent when complete statistics information has been collected for the task.
    func dataLoader(_ loader: DataLoader, urlSession: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics)
}

@available(*, deprecated, message: "Please use `DataLoader/delegate` instead")
extension DataLoaderObserving {
    public func dataLoader(_ loader: DataLoader, urlSession: URLSession, dataTask: URLSessionDataTask, didReceiveEvent event: DataTaskEvent) {
        // Do nothing
    }

    public func dataLoader(_ loader: DataLoader, urlSession: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        // Do nothing
    }
}

/// Deprecated in Nuke 11.1
public enum DataTaskEvent {
    case resumed
    case receivedResponse(response: URLResponse)
    case receivedData(data: Data)
    case completed(error: Error?)
}

// Deprecated in Nuke 11.1
protocol _DataLoaderObserving: AnyObject {
    func dataTask(_ dataTask: URLSessionDataTask, didReceiveEvent event: DataTaskEvent)
    func task(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics)
}

extension ImagePipeline {
    @available(*, deprecated, message: "Please use either `loadData` that accepts `ImageRequest` as a parameter or, preferably, the new async/await APIs")
    @discardableResult public func loadData(
        with request: any ImageRequestConvertible,
        completion: @escaping (Result<(data: Data, response: URLResponse?), Error>) -> Void
    ) -> ImageTask {
        loadData(with: request.asImageRequest(), queue: nil, progress: nil, completion: completion)
    }

    @available(*, deprecated, message: "Please use either `loadData` that accepts `ImageRequest` as a parameter or, preferably, the new async/await APIs")
    @discardableResult public func loadData(
        with request: any ImageRequestConvertible,
        queue: DispatchQueue? = nil,
        progress: ((_ completed: Int64, _ total: Int64) -> Void)?,
        completion: @escaping (Result<(data: Data, response: URLResponse?), Error>) -> Void
    ) -> ImageTask {
        loadData(with: request.asImageRequest(), isConfined: false, queue: queue, progress: progress, completion: completion)
    }

    @available(*, deprecated, message: "Please use either `loadImage` that accepts `ImageRequest` as a parameter or, preferably, the new async/await APIs")
    @discardableResult public func loadImage(
        with request: any ImageRequestConvertible,
        completion: @escaping (_ result: Result<ImageResponse, Error>) -> Void
    ) -> ImageTask {
        loadImage(with: request.asImageRequest(), queue: nil, progress: nil, completion: completion)
    }

    @available(*, deprecated, message: "Please use either `loadImage` that accepts `ImageRequest` as a parameter or, preferably, the new async/await APIs")
    @discardableResult public func loadImage(
        with request: any ImageRequestConvertible,
        queue: DispatchQueue? = nil,
        progress: ((_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)?,
        completion: @escaping (_ result: Result<ImageResponse, Error>) -> Void
    ) -> ImageTask {
        loadImage(with: request.asImageRequest(), isConfined: false, queue: queue, progress: {
            progress?($0, $1.completed, $1.total)
        }, completion: completion)
    }
}
