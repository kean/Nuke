// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - Removed in Nuke 14
//
// Removed APIs are kept as unavailable stubs that name their replacement: the
// message goes straight into the compiler error, and `renamed:` also becomes an
// Xcode fix-it. They are deleted two major versions after the removal.

/// - warning: Renamed to ``ImagePipeline/Delegate``.
@available(*, unavailable, renamed: "ImagePipeline.Delegate")
public typealias ImagePipelineDelegate = ImagePipeline.Delegate

extension ImageRequest {
    @available(*, unavailable, renamed: "imageID")
    public var imageId: String? {
        get { fatalError() }
        set { fatalError() }
    }

    @available(*, unavailable, message: "Removed in Nuke 14. Set the `userInfo` property on the request instead.")
    public init(url: URL?, processors: [any ImageProcessing] = [], priority: Priority = .normal, options: Options = [], userInfo: [UserInfoKey: any Sendable]?) {
        fatalError()
    }

    @available(*, unavailable, message: "Removed in Nuke 14. Set the `userInfo` property on the request instead.")
    public init(urlRequest: URLRequest, processors: [any ImageProcessing] = [], priority: Priority = .normal, options: Options = [], userInfo: [UserInfoKey: any Sendable]?) {
        fatalError()
    }

    @available(*, unavailable, message: "Removed in Nuke 14. Set the `userInfo` property on the request instead.")
    public init(id: String, data: @Sendable @escaping () async throws -> Data, processors: [any ImageProcessing] = [], priority: Priority = .normal, options: Options = [], userInfo: [UserInfoKey: any Sendable]?) {
        fatalError()
    }

    @available(*, unavailable, message: "Removed in Nuke 14. Set the `userInfo` property on the request instead.")
    public init(id: String, image: @Sendable @escaping () async throws -> ImageContainer, processors: [any ImageProcessing] = [], priority: Priority = .normal, options: Options = [], userInfo: [UserInfoKey: any Sendable]?) {
        fatalError()
    }
}

extension ImageRequest.UserInfoKey {
    @available(*, unavailable, message: "Removed in Nuke 14. Use `ImageRequest.imageID`.")
    public static let imageIdKey: ImageRequest.UserInfoKey = "github.com/kean/nuke/imageId"

    @available(*, unavailable, message: "Removed in Nuke 14. Use `ImageRequest.scale`.")
    public static let scaleKey: ImageRequest.UserInfoKey = "github.com/kean/nuke/scale"

    @available(*, unavailable, message: "Removed in Nuke 14. Use `ImageRequest.thumbnail`.")
    public static let thumbnailKey: ImageRequest.UserInfoKey = "github.com/kean/nuke/thumbnail"
}

extension ImagePipeline.Configuration {
    @available(*, unavailable, message: "Removed in Nuke 14. Automatic downscaling is gone; use `ImageRequest.ThumbnailOptions` per request.")
    public var maximumDecodedImageSize: Int? {
        get { fatalError() }
        set { fatalError() }
    }

    @available(*, unavailable, message: "Removed in Nuke 14. The pipeline sends signposts while its diagnostics are on; see `isDiagnosticsEnabled` and `signpostLog`.")
    public static var isSignpostLoggingEnabled: Bool {
        get { fatalError() }
        set { fatalError() }
    }
}

extension ImageDecodingContext {
    @available(*, unavailable, message: "Removed in Nuke 14. Automatic downscaling is gone; use `ImageRequest.ThumbnailOptions` per request.")
    public var maximumDecodedImageSize: Int? {
        get { fatalError() }
        set { fatalError() }
    }
}

extension ImagePipeline {
    @available(*, unavailable, message: "Removed in Nuke 14. Use `image(for:)` or `imageTask(with:)`. For progressive previews use `ImageTask.previews`.")
    nonisolated public func imagePublisher(with url: URL) -> Never { fatalError() }

    @available(*, unavailable, message: "Removed in Nuke 14. Use `image(for:)` or `imageTask(with:)`. For progressive previews use `ImageTask.previews`.")
    nonisolated public func imagePublisher(with request: ImageRequest) -> Never { fatalError() }
}

// MARK: - Removed Before Nuke 14
//
// These are not for migrations. Most of the Swift that mentions Nuke was written
// against older versions, and that is the code people remember and models learned
// from. Without a stub, an old name fails with "no member", which says nothing
// about what to use instead.
//
// They have no removal date: the stubs don't show up in code completion or in the
// documentation, so they cost nothing to keep. Limited to the names with at least
// 20 matches in the Swift code on GitHub, and only the ones that are safe to stub:
// a property that used to be followed by another member, such as
// `memoryCacheOptions.isReadAllowed`, would fail on the member, not on the stub.

@available(*, unavailable, renamed: "ImagePrefetcher", message: "Renamed in Nuke 10.")
public typealias ImagePreheater = ImagePrefetcher

@available(*, unavailable, renamed: "ImageDecoders.Default", message: "Renamed in Nuke 10. The pipeline uses it by default, so you rarely need to create one.")
public typealias ImageDecoder = ImageDecoders.Default

@available(*, unavailable, renamed: "ImageTask.Event", message: "Renamed in Nuke 11.")
public typealias ImageTaskEvent = ImageTask.Event

@available(*, unavailable, renamed: "ImageRequest.Options", message: "Renamed in Nuke 10.")
public typealias ImageRequestOptions = ImageRequest.Options

@available(*, unavailable, message: "Removed in Nuke 10. Pass `ImagePipeline.Delegate` to the pipeline initializer, and implement `imageTask(_:didReceiveEvent:pipeline:)`.")
public typealias ImagePipelineObserving = ImagePipeline.Delegate

@available(*, unavailable, message: "Removed in Nuke 12. Pass a `URL` or an `ImageRequest`.")
public typealias ImageRequestConvertible = ImageRequest

@available(*, unavailable, message: "Moved out of the core module. Use `ImageLoader.load(_:into:)` from NukeUI, or `loadImage(with:into:)` from NukeExtensions, which is soft-deprecated.")
public func loadImage(with url: URL?, options: Any? = nil, into view: Any, progress: Any? = nil, completion: ((Any) -> Void)? = nil) {
    fatalError("Removed")
}

@available(*, unavailable, message: "Moved out of the core module. Use `ImageLoader.load(_:into:)` from NukeUI, or `loadImage(with:into:)` from NukeExtensions, which is soft-deprecated.")
public func loadImage(with request: ImageRequest?, options: Any? = nil, into view: Any, progress: Any? = nil, completion: ((Any) -> Void)? = nil) {
    fatalError("Removed")
}

@available(*, unavailable, message: "Moved out of the core module. Use `ImageLoader.Presentation` from NukeUI, or import NukeExtensions, which is soft-deprecated.")
// swiftlint:disable:next convenience_type
public struct ImageLoadingOptions {
    public enum Transition {
        @available(*, unavailable)
        public static func fadeIn(duration: TimeInterval, options: Any? = nil) -> Transition { fatalError("Removed") }
    }

    @available(*, unavailable)
    public init(placeholder: Any? = nil, transition: Transition? = nil, failureImage: Any? = nil, failureImageTransition: Transition? = nil, contentModes: Any? = nil, tintColors: Any? = nil) {
        fatalError("Removed")
    }
}

extension ImagePipeline.Configuration {
    @available(*, unavailable, renamed: "isTaskCoalescingEnabled", message: "Renamed in Nuke 10.")
    public var isDeduplicationEnabled: Bool {
        get { fatalError("Removed") }
        set { fatalError("Removed") }
    }

    @available(*, unavailable, message: "Removed in Nuke 10. Animated images need no setup: the pipeline attaches them to `ImageContainer.data` and `ImageContainer.animation`, and `LazyImage` plays them. To skip parsing them, use `isAnimatedImageParsingEnabled`.")
    public var isAnimatedImageDataEnabled: Bool {
        get { fatalError("Removed") }
        set { fatalError("Removed") }
    }

    @available(*, unavailable, message: "Removed in Nuke 10. Animated images need no setup: the pipeline attaches them to `ImageContainer.data` and `ImageContainer.animation`, and `LazyImage` plays them. To skip parsing them, use `isAnimatedImageParsingEnabled`.")
    public static var isAnimatedImageDataEnabled: Bool {
        get { fatalError("Removed") }
        set { fatalError("Removed") }
    }

    @available(*, unavailable, message: "Removed in Nuke 13. The closure-based APIs call back on the main actor.")
    public var callbackQueue: DispatchQueue {
        get { fatalError("Removed") }
        set { fatalError("Removed") }
    }

    @available(*, unavailable, message: "Removed in Nuke 13. `DataCache` schedules its own writes.")
    public var dataCachingQueue: TaskQueue {
        get { fatalError("Removed") }
        set { fatalError("Removed") }
    }
}

extension ImageRequest.Options {
    @available(*, unavailable, renamed: "disableMemoryCacheReads")
    public static var disableMemoryCacheRead: ImageRequest.Options { fatalError("Removed") }

    @available(*, unavailable, renamed: "disableMemoryCacheWrites")
    public static var disableMemoryCacheWrite: ImageRequest.Options { fatalError("Removed") }

    @available(*, unavailable, renamed: "disableDiskCacheReads")
    public static var disableDiskCacheRead: ImageRequest.Options { fatalError("Removed") }

    @available(*, unavailable, renamed: "disableDiskCacheWrites")
    public static var disableDiskCacheWrite: ImageRequest.Options { fatalError("Removed") }
}

extension ImageTask {
    @available(*, unavailable, message: "Removed in Nuke 12. Use `status.progress.completed`, or observe `progress`.")
    public var completedUnitCount: Int64 { fatalError("Removed") }

    @available(*, unavailable, message: "Removed in Nuke 12. Use `status.progress.total`, or observe `progress`.")
    public var totalUnitCount: Int64 { fatalError("Removed") }
}

// MARK: - Soft-deprecated in Nuke 12.9

extension ImagePipeline {
    // MARK: - Loading Images (Closures)

    /// - warning: Soft-deprecated in Nuke 12.9.
    @discardableResult nonisolated public func loadImage(with url: URL, completion: @escaping @MainActor @Sendable (_ result: Result<ImageResponse, Error>) -> Void) -> ImageTask {
        _loadImage(with: ImageRequest(url: url), progress: nil, completion: completion)
    }

    /// - warning: Soft-deprecated in Nuke 12.9.
    @discardableResult nonisolated public func loadImage(with request: ImageRequest, completion: @escaping @MainActor @Sendable (_ result: Result<ImageResponse, Error>) -> Void) -> ImageTask {
        _loadImage(with: request, progress: nil, completion: completion)
    }

    /// - warning: Soft-deprecated in Nuke 12.9.
    @discardableResult nonisolated public func loadImage(with request: ImageRequest, progress: (@MainActor @Sendable (_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)?, completion: @escaping @MainActor @Sendable (_ result: Result<ImageResponse, Error>) -> Void) -> ImageTask {
        _loadImage(with: request, progress: {
            progress?($0, $1.completed, $1.total)
        }, completion: completion)
    }

    nonisolated func _loadImage(
        with request: ImageRequest,
        isDataTask: Bool = false,
        progress: (@MainActor @Sendable (ImageResponse?, ImageTask.Progress) -> Void)?,
        completion: @escaping @MainActor @Sendable (Result<ImageResponse, Error>) -> Void
    ) -> ImageTask {
        makeStartedImageTask(with: request, isDataTask: isDataTask) { event, task in
            let work: @MainActor @Sendable () -> Void = {
                // The callback-based API guarantees that after cancellation no
                // events are called on the callback queue.
                guard !task.isCancelled else { return }
                switch event {
                case .progress(let value): progress?(nil, value)
                case .preview(let response): progress?(response, task.status.progress)
                case .finished(let result):
                    completion(result)
                }
            }
            DispatchQueue.main.async(execute: work)
        }
    }

    // MARK: - Loading Data (Closures)

    /// - warning: Soft-deprecated in Nuke 12.9.
    @discardableResult nonisolated public func loadData(with request: ImageRequest, completion: @escaping @MainActor @Sendable (Result<(data: Data, response: URLResponse?), Error>) -> Void) -> ImageTask {
        _loadImage(with: request, isDataTask: true, progress: nil) { result in
            let result = result.map { response in
                (data: response.container.data ?? Data(), response: response.urlResponse)
            }
            completion(result)
        }
    }

    /// - warning: Soft-deprecated in Nuke 12.9.
    @discardableResult nonisolated public func loadData(with request: ImageRequest, progress progressHandler: (@MainActor @Sendable (_ completed: Int64, _ total: Int64) -> Void)?, completion: @escaping @MainActor @Sendable (Result<(data: Data, response: URLResponse?), Error>) -> Void) -> ImageTask {
        _loadImage(with: request, isDataTask: true) { _, progress in
            progressHandler?(progress.completed, progress.total)
        } completion: { result in
            let result = result.map { response in
                (data: response.container.data ?? Data(), response: response.urlResponse)
            }
            completion(result)
        }
    }
}
