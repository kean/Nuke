// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImagePipeline {
    /// Loads an image for the given request.
    ///
    /// - warning: Soft-deprecated in Nuke 13.0.
    ///
    /// - parameters:
    ///   - request: An image request.
    ///   - completion: A closure to be called on the main thread when the request
    ///   is finished.
    @discardableResult public nonisolated func loadImage(
        with url: URL,
        completion: @MainActor @Sendable @escaping (_ result: Result<ImageResponse, ImageTask.Error>) -> Void
    ) -> ImageTask {
        _loadImage(with: ImageRequest(url: url), progress: nil, completion: completion)
    }

    /// Loads an image for the given request.
    ///
    /// - warning: Soft-deprecated in Nuke 13.0.
    ///
    /// - parameters:
    ///   - request: An image request.
    ///   - completion: A closure to be called on the main thread when the request
    ///   is finished.
    @discardableResult public nonisolated func loadImage(
        with request: ImageRequest,
        completion: @MainActor @Sendable @escaping (_ result: Result<ImageResponse, ImageTask.Error>) -> Void
    ) -> ImageTask {
        _loadImage(with: request, progress: nil, completion: completion)
    }

    /// Loads an image for the given request.
    ///
    /// - warning: Soft-deprecated in Nuke 13.0.
    ///
    /// - parameters:
    ///   - request: An image request.
    ///   - progress: A closure to be called periodically on the main thread when
    ///   the progress is updated.
    ///   - completion: A closure to be called on the main thread when the request
    ///   is finished.
    @discardableResult public nonisolated func loadImage(
        with request: ImageRequest,
        progress: (@MainActor @Sendable (_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)?,
        completion: @MainActor @Sendable @escaping (_ result: Result<ImageResponse, ImageTask.Error>) -> Void
    ) -> ImageTask {
        _loadImage(with: request, progress: {
            progress?($0, $1.completed, $1.total)
        }, completion: completion)
    }

    /// Loads the image data for the given request. The data doesn't get decoded
    /// or processed in any other way.
    ///
    /// You can call ``loadImage(with:completion:)-43osv`` for the request at any point after calling
    /// ``loadData(with:completion:)-6cwk3``, the pipeline will use the same operation to load the data,
    /// no duplicated work will be performed.
    ///
    /// - warning: Soft-deprecated in Nuke 13.0.
    ///
    /// - parameters:
    ///   - request: An image request.
    ///   - progress: A closure to be called periodically on the main thread when the progress is updated.
    ///   - completion: A closure to be called on the main thread when the request is finished.
    @discardableResult public nonisolated func loadData(
        with request: ImageRequest,
        progress progressHandler: (@MainActor @Sendable (_ completed: Int64, _ total: Int64) -> Void)? = nil,
        completion: @MainActor @Sendable @escaping (Result<(data: Data, response: URLResponse?), ImageTask.Error>) -> Void
    ) -> ImageTask {
        _loadImage(with: request, isDataTask: true) { _, progress in
            progressHandler?(progress.completed, progress.total)
        } completion: { result in
            let result = result.map { response in
                // Data should never be empty
                (data: response.container.data ?? Data(), response: response.urlResponse)
            }
            completion(result)
        }
    }

    private nonisolated func _loadImage(
        with request: ImageRequest,
        isDataTask: Bool = false,
        progress: (@MainActor @Sendable (ImageResponse?, ImageTask.Progress) -> Void)?,
        completion: @MainActor @Sendable @escaping (Result<ImageResponse, ImageTask.Error>) -> Void
    ) -> ImageTask {
        makeImageTask(with: request, isDataTask: isDataTask) { event, task in
            DispatchQueue.main.async {
                // The callback-based API guarantees that after cancellation no
                // event are called on the callback queue.
                guard !task.isCancelling else { return }
                switch event {
                case .progress(let value): progress?(nil, value)
                case .preview(let response): progress?(response, task.currentProgress)
                case .cancelled: break // The legacy APIs do not send cancellation events
                case .finished(let result): completion(result)
                }
            }
        }.resume()
    }
}

extension ImageTask {
    @discardableResult nonisolated func resume() -> ImageTask {
        Task { @ImagePipelineActor in
            _ = try? await response
        }
        return self
    }
}
