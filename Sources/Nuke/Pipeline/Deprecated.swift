// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImagePipeline {
    // MARK: - Loading Images (Closures)

    /// Loads an image for the given request.
    ///
    /// - warning: Soft-deprecated in Nuke 12.9.
    ///
    /// - parameters:
    ///   - request: An image request.
    ///   - completion: A closure to be called on the main thread when the request
    ///   is finished.
    @discardableResult public func loadImage(
        with url: URL,
        completion: @escaping @MainActor @Sendable (_ result: Result<ImageResponse, Error>) -> Void
    ) -> ImageTask {
        _loadImage(with: ImageRequest(url: url), progress: nil, completion: completion)
    }

    /// Loads an image for the given request.
    ///
    /// - warning: Soft-deprecated in Nuke 12.9.
    ///
    /// - parameters:
    ///   - request: An image request.
    ///   - completion: A closure to be called on the main thread when the request
    ///   is finished.
    @discardableResult public func loadImage(
        with request: ImageRequest,
        completion: @escaping @MainActor @Sendable (_ result: Result<ImageResponse, Error>) -> Void
    ) -> ImageTask {
        _loadImage(with: request, progress: nil, completion: completion)
    }

    /// Loads an image for the given request.
    ///
    /// - warning: Soft-deprecated in Nuke 12.9.
    ///
    /// - parameters:
    ///   - request: An image request.
    ///   - progress: A closure to be called periodically on the main thread when
    ///   the progress is updated.
    ///   - completion: A closure to be called on the main thread when the request
    ///   is finished.
    @discardableResult public func loadImage(
        with request: ImageRequest,
        progress: (@MainActor @Sendable (_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)?,
        completion: @escaping @MainActor @Sendable (_ result: Result<ImageResponse, Error>) -> Void
    ) -> ImageTask {
        _loadImage(with: request, progress: {
            progress?($0, $1.completed, $1.total)
        }, completion: completion)
    }

    func _loadImage(
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
                case .cancelled: break // The legacy APIs do not send cancellation events
                case .finished(let result):
                    _ = task._setState(.completed) // Important to do it on the callback queue
                    completion(result)
                }
            }
            DispatchQueue.main.async(execute: work)
        }
    }

    // MARK: - Loading Data (Closures)

    /// Loads image data for the given request. The data doesn't get decoded
    /// or processed in any other way.
    ///
    /// - warning: Soft-deprecated in Nuke 12.9.
    @discardableResult public func loadData(with request: ImageRequest, completion: @escaping @MainActor @Sendable (Result<(data: Data, response: URLResponse?), Error>) -> Void) -> ImageTask {
        _loadImage(with: request, isDataTask: true, progress: nil) { result in
            let result = result.map { response in
                (data: response.container.data ?? Data(), response: response.urlResponse)
            }
            completion(result)
        }
    }

    /// Loads the image data for the given request. The data doesn't get decoded
    /// or processed in any other way.
    ///
    /// You can call ``loadImage(with:completion:)-43osv`` for the request at any point after calling
    /// ``loadData(with:completion:)-6cwk3``, the pipeline will use the same operation to load the data,
    /// no duplicated work will be performed.
    ///
    /// - parameters:
    ///   - request: An image request.
    ///   - progress: A closure to be called periodically on the main thread when the progress is updated.
    ///   - completion: A closure to be called on the main thread when the request is finished.
    @discardableResult public func loadData(
        with request: ImageRequest,
        progress progressHandler: (@MainActor @Sendable (_ completed: Int64, _ total: Int64) -> Void)?,
        completion: @escaping @MainActor @Sendable (Result<(data: Data, response: URLResponse?), Error>) -> Void
    ) -> ImageTask {
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
