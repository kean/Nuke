// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

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

    /// The events sent by the pipeline during the task execution.
    public let events: AsyncStream<ImageTask.Event>

    // Deprecated in Nuke 12.7
    @available(*, deprecated, message: "Please use `events` instead")
    public var previews: AsyncStream<ImageResponse> { _previews }

    var _previews: AsyncStream<ImageResponse> {
        AsyncStream { continuation in
            Task {
                for await event in events {
                    if case .preview(let preview) = event {
                        continuation.yield(preview)
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Returns the current download progress. Returns zeros before the download
    /// is started and the expected size of the resource is known.
    public var progress: AsyncStream<ImageTask.Progress> {
        AsyncStream { continuation in
            Task {
                for await event in events {
                    if case .progress(let progress) = event {
                        continuation.yield(progress)
                    }
                }
                continuation.finish()
            }
        }
    }

    init(imageTask: ImageTask,
         task: Task<ImageResponse, Error>,
         events: AsyncStream<ImageTask.Event>) {
        self.imageTask = imageTask
        self.task = task
        self.events = events
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
    var events: AsyncStream<ImageTask.Event>.Continuation?
}
