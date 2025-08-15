// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// A task performed by the ``ImagePipeline``.
///
/// The pipeline maintains a strong reference to the task until the request
/// finishes or fails; you do not need to maintain a reference to the task unless
/// it is useful for your app.
@ImagePipelineActor
public final class ImageTask: Hashable, JobSubscriber {
    /// An identifier that uniquely identifies the task within a given pipeline.
    /// Unique only within that pipeline.
    public nonisolated let taskId: Int64

    /// The original request that the task was created with.
    public nonisolated let request: ImageRequest

    /// The priority of the task. The priority can be updated dynamically even
    /// for a task that is already running.
    public nonisolated var priority: ImageRequest.Priority {
        get { nonisolatedState.withLock(\.priority) }
        set { setPriority(newValue) }
    }

    /// Returns the current download progress. Returns zeros before the download
    /// is started and the expected size of the resource is known.
    public nonisolated var currentProgress: Progress {
        nonisolatedState.withLock(\.progress)
    }

    /// The current state of the task.
    public private(set) var state: State = .suspended

    /// Returns `true` if the task cancellation is initiated.
    public nonisolated var isCancelling: Bool {
        nonisolatedState.withLock(\.isCancelling)
    }

    // MARK: - Async/Await

    /// Returns the response image.
    public var image: PlatformImage {
        get async throws(ImageTask.Error) {
            try await perform().image
        }
    }

    /// Returns the image response.
    public var response: ImageResponse {
        get async throws(ImageTask.Error) {
            try await perform()
        }
    }

    /// The stream of progress updates.
    public nonisolated var progress: AsyncCompactMapSequence<AsyncStream<Event>, Progress> {
        events.compactMap {
            if case .progress(let value) = $0 { return value }
            return nil
        }
    }

    /// The stream of image previews generated for images that support
    /// progressive decoding.
    ///
    /// - seealso: ``ImagePipeline/Configuration-swift.struct/isProgressiveDecodingEnabled``
    public nonisolated var previews: AsyncCompactMapSequence<AsyncStream<Event>, ImageResponse> {
        events.compactMap {
            if case .preview(let value) = $0 { return value }
            return nil
        }
    }

    /// The events sent by the pipeline during the task execution.
    public nonisolated var events: AsyncStream<Event> {
        AsyncStream { continuation in
            Task { @ImagePipelineActor in
                if case .suspended = state {
                    startRunning()
                }
                guard case .running = state else {
                    return continuation.finish()
                }
                streamContinuations.append(continuation)
            }
        }
    }

    let isDataTask: Bool
    private let nonisolatedState: Mutex<ImageTaskState>
    private let onEvent: (@ImagePipelineActor @Sendable (Event, ImageTask) -> Void)?
    private weak var pipeline: ImagePipeline?
    private var subscription: JobSubscription?

    private var taskContinuations = ContiguousArray<UnsafeContinuation<ImageResponse, Swift.Error>>()
    private var streamContinuations = ContiguousArray<AsyncStream<ImageTask.Event>.Continuation>()

    nonisolated init(taskId: Int64, request: ImageRequest, isDataTask: Bool, pipeline: ImagePipeline, onEvent: (@ImagePipelineActor @Sendable (Event, ImageTask) -> Void)?) {
        self.taskId = taskId
        self.request = request
        self.nonisolatedState = Mutex(ImageTaskState(priority: request.priority))
        self.isDataTask = isDataTask
        self.pipeline = pipeline
        self.onEvent = onEvent
    }

    private func perform() async throws(ImageTask.Error) -> ImageResponse {
        do {
//            return try await withTaskCancellationHandler {
                return try await withUnsafeThrowingContinuation { continuation in
                    switch state {
                        case .suspended:
                            taskContinuations.append(continuation)
                            startRunning()
                        case .running:
                            taskContinuations.append(continuation)
                        case .cancelled:
                            continuation.resume(throwing: ImageTask.Error.cancelled)
                        case .completed(let result):
                            continuation.resume(with: result)
                    }
                }
//            } onCancel: {
//                cancel()
//            }

        } catch {
            // swiftlint:disable:next force_cast
            throw error as! ImageTask.Error
        }
    }

    private func startRunning() {
        state = .running
        subscription = pipeline?.perform(self)
    }

    /// Marks task as being cancelled.
    ///
    /// The pipeline will immediately cancel any work associated with a task
    /// unless there is an equivalent outstanding task running.
    public nonisolated func cancel() {
        guard nonisolatedState.withLock({
            guard !$0.isCancelling else { return false }
            $0.isCancelling = true
            return true
        }) else { return }
        Task { @ImagePipelineActor in
            _cancel()
        }
    }

    private nonisolated func setPriority(_ newValue: ImageRequest.Priority) {
        guard nonisolatedState.withLock({
            guard $0.priority != newValue else { return false }
            $0.priority = newValue
            return !$0.isCancelling
        }) else { return }
        Task { @ImagePipelineActor in
            subscription?.didChangePriority(newValue)
        }
    }

    // MARK: Internals

    /// Gets called when the task is cancelled either by the user or by an
    /// external event such as session invalidation.
    func _cancel() {
        guard case .running = state else { return }
        subscription?.unsubscribe()
        subscription = nil
        state = .cancelled
        dispatch(.cancelled)
    }

    /// Dispatches the given event to the observers.
    ///
    /// - warning: The task needs to be fully wired (`_continuation` present)
    /// before it can start sending the events.
    private func dispatch(_ event: Event) {
        for continuation in streamContinuations {
            continuation.yield(event)
        }

        func complete(with result: Result<ImageResponse, ImageTask.Error>) {
            subscription = nil

            for continuation in streamContinuations {
                continuation.finish()
            }
            streamContinuations.removeAll()

            for continuation in taskContinuations {
                continuation.resume(with: result)
            }
            taskContinuations.removeAll()
        }

        switch event {
        case .cancelled:
            complete(with: .failure(.cancelled))
        case .finished(let result):
            complete(with: result)
        default:
            break
        }

        onEvent?(event, self)
        pipeline?.imageTask(self, didProcessEvent: event)
    }

    // MARK: JobSubscriber

    func receive(_ event: Job<ImageResponse>.Event) {
        guard case .running = state else { return }
        switch event {
        case let .value(response, isCompleted):
            if isCompleted {
                state = .completed(.success(response))
                dispatch(.finished(.success(response)))
            } else {
                dispatch(.preview(response))
            }
        case let .progress(value):
            nonisolatedState.withLock { $0.progress = value }
            dispatch(.progress(value))
        case let .error(error):
            state = .completed(.failure(error))
            dispatch(.finished(.failure(error)))
        }
    }

    func addSubscribedTasks(to output: inout [ImageTask]) {
        output.append(self)
    }

    // MARK: Hashable

    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self).hashValue)
    }

    public nonisolated static func == (lhs: ImageTask, rhs: ImageTask) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}

private struct ImageTaskState {
    var isCancelling = false
    var priority: ImageRequest.Priority
    var progress = ImageTask.Progress(completed: 0, total: 0)
}

extension ImageTask {
    /// The download progress.
    public struct Progress: Hashable, Sendable {
        /// The number of bytes that the task has received.
        public let completed: Int64
        /// A best-guess upper bound on the number of bytes of the resource.
        public let total: Int64

        /// Returns the fraction of the completion.
        public var fraction: Float {
            guard total > 0 else { return 0 }
            return min(1, Float(completed) / Float(total))
        }

        /// Initializes progress with the given status.
        public init(completed: Int64, total: Int64) {
            (self.completed, self.total) = (completed, total)
        }
    }

    /// The state of the image task.
    public enum State: Sendable {
        /// The initial state.
        case suspended
        /// The task is currently running.
        case running
        /// The task has received a cancel message.
        case cancelled
        /// The task has completed (without being canceled).
        case completed(Result<ImageResponse, ImageTask.Error>)
    }

    /// An event produced during the runetime of the task.
    public enum Event: Sendable {
        /// The download progress was updated.
        case progress(Progress)
        /// The pipeline generated a progressive scan of the image.
        case preview(ImageResponse)
        /// The task was cancelled.
        ///
        /// - note: You are guaranteed to receive either `.cancelled` or
        /// `.finished`, but never both.
        case cancelled
        /// The task finish with the given response.
        case finished(Result<ImageResponse, ImageTask.Error>)
    }

        /// Represents all possible image task errors.
    public enum Error: Swift.Error, CustomStringConvertible, Sendable {
        /// The task got cancelled.
        ///
        /// - warning: This error case is used only for Async/Await APIs. The
        /// completion-based APIs don't report cancellation error for backward
        /// compatibility.
        case cancelled
        /// Returned if data not cached and ``ImageRequest/Options-swift.struct/returnCacheDataDontLoad`` option is specified.
        case dataMissingInCache
        /// Data loader failed to load image data with a wrapped error.
        case dataLoadingFailed(error: Swift.Error)
        /// Data loader returned empty data.
        case dataIsEmpty
        /// No decoder registered for the given data.
        ///
        /// This error can only be thrown if the pipeline has custom decoders.
        /// By default, the pipeline uses ``ImageDecoders/Default`` as a catch-all.
        case decoderNotRegistered(context: ImageDecodingContext)
        /// Decoder failed to produce a final image.
        case decodingFailed(decoder: any ImageDecoding, context: ImageDecodingContext, error: Swift.Error)
        /// Processor failed to produce a final image.
        case processingFailed(processor: any ImageProcessing, context: ImageProcessingContext, error: Swift.Error)
        /// Load image method was called with no image request.
        case imageRequestMissing
        /// Image pipeline is invalidated and no requests can be made.
        case pipelineInvalidated
    }
}

extension ImageTask.Error {
    /// Returns underlying data loading error.
    public var dataLoadingError: Swift.Error? {
        switch self {
        case .dataLoadingFailed(let error):
            return error
        default:
            return nil
        }
    }

    public var description: String {
        switch self {
        case .dataMissingInCache:
            return "Failed to load data from cache and download is disabled."
        case let .dataLoadingFailed(error):
            return "Failed to load image data. Underlying error: \(error)."
        case .dataIsEmpty:
            return "Data loader returned empty data."
        case .decoderNotRegistered:
            return "No decoders registered for the downloaded data."
        case let .decodingFailed(decoder, _, error):
            let underlying = error is ImageDecodingError ? "" : " Underlying error: \(error)."
            return "Failed to decode image data using decoder \(decoder).\(underlying)"
        case let .processingFailed(processor, _, error):
            let underlying = error is ImageProcessingError ? "" : " Underlying error: \(error)."
            return "Failed to process the image using processor \(processor).\(underlying)"
        case .imageRequestMissing:
            return "Load image method was called with no image request or no URL."
        case .pipelineInvalidated:
            return "Image pipeline is invalidated and no requests can be made."
        case .cancelled:
            return "Image task was cancelled"
        }
    }
}
