// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// - warning: Renamed to ``ImagePipeline/Delegate``.
@available(*, deprecated, renamed: "ImagePipeline.Delegate")
public typealias ImagePipelineDelegate = ImagePipeline.Delegate

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
                guard task.state != .cancelled else { return }
                switch event {
                case .started: break
                case .progress(let value): progress?(nil, value)
                case .preview(let response): progress?(response, task.currentProgress)
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
