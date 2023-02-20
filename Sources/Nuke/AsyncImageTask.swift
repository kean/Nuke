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

    /// Returns the current download progress. Returns zeros before the download
    /// is started and the expected size of the resource is known.
    public let progress: AsyncStream<ImageTask.Progress>

    init(imageTask: ImageTask, task: Task<ImageResponse, Error>, progress: AsyncStream<ImageTask.Progress>) {
        self.imageTask = imageTask
        self.task = task
        self.progress = progress
    }

    /// Marks task as being cancelled.
    ///
    /// The pipeline will immediately cancel any work associated with a task
    /// unless there is an equivalent outstanding task running.
    public func cancel() {
        imageTask.cancel()
    }
}

final class AsyncTaskContext {
    var progress: AsyncStream<ImageTask.Progress>.Continuation?
}
