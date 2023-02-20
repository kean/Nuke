// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A task performed by the ``ImagePipeline``.
public final class AsyncImageTask: Sendable {
    private let imageTask: ImageTask
    private let task: Task<ImageResponse, Error>

    /// Updates the priority of the task, even if it is already running.
    public var priority: ImageRequest.Priority {
        get { imageTask.priority }
        set { imageTask.priority = newValue }
    }

    /// The fetched image.
    public var image: PlatformImage {
        get async throws {
            try await response.image
        }
    }

    /// The image response.
    public var response: ImageResponse {
        get async throws {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                self.cancel()
            }
        }
    }

    init(imageTask: ImageTask, task: Task<ImageResponse, Error>) {
        self.imageTask = imageTask
        self.task = task
    }

    /// Marks task as being cancelled.
    ///
    /// The pipeline will immediately cancel any work associated with a task
    /// unless there is an equivalent outstanding task running.
    public func cancel() {
        imageTask.cancel()
    }
}
