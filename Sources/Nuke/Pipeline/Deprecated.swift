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
