// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// A task performed by the ``ImagePipeline``. Use ``ImagePipeline/imageTask(with:)-7s0fc``
/// to create a task.
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

    /// Returns all images responses including the previews for progressive images.
    public let previews: AsyncStream<ImageResponse>

    /// Returns the current download progress. Returns zeros before the download
    /// is started and the expected size of the resource is known.
    public let progress: AsyncStream<ImageTask.Progress>

    init(imageTask: ImageTask,
         task: Task<ImageResponse, Error>,
         progress: AsyncStream<ImageTask.Progress>,
         previews: AsyncStream<ImageResponse>) {
        self.imageTask = imageTask
        self.task = task
        self.progress = progress
        self.previews = previews
    }

    /// Marks task as being cancelled.
    ///
    /// The pipeline will immediately cancel any work associated with a task
    /// unless there is an equivalent outstanding task running.
    public func cancel() {
        imageTask.cancel()
    }
}

// Making it Sendable because the closures are set once right after initialization
// and are never mutated afterward.
final class AsyncTaskContext: @unchecked Sendable {
    var progress: AsyncStream<ImageTask.Progress>.Continuation?
    var previews: AsyncStream<ImageResponse>.Continuation?
}
