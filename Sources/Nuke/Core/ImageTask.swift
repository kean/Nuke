// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A task performed by the `ImagePipeline`.
///
/// The pipeline maintains a strong reference to the task until the request
/// finishes or fails; you do not need to maintain a reference to the task unless
/// it is useful for your app.
public final class ImageTask: Hashable, CustomStringConvertible, @unchecked Sendable {
    /// An identifier that uniquely identifies the task within a given pipeline.
    /// Unique only within that pipeline.
    public let taskId: Int64

    /// The original request.
    public let request: ImageRequest

    let isDataTask: Bool

    /// Updates the priority of the task, even if it is already running.
    public func setPriority(_ priority: ImageRequest.Priority) {
        pipeline?.imageTaskUpdatePriorityCalled(self, priority: priority)
    }
    var _priority: ImageRequest.Priority // Backing store for access from pipeline only
    // Putting all smaller units closer together (1 byte / 1 byte)

    // MARK: Progress

    /// The number of bytes that the task has received.
    public private(set) var completedUnitCount: Int64 = 0

    /// A best-guess upper bound on the number of bytes of the resource.
    public private(set) var totalUnitCount: Int64 = 0

    /// Returns a progress object for the task, created lazily.
    public var progress: Progress {
        if _progress == nil { _progress = Progress() }
        return _progress!
    }
    private var _progress: Progress?

    var isCancelled: Bool { _isCancelled.pointee == 1 }
    private let _isCancelled: UnsafeMutablePointer<Int32>

    var onCancel: (() -> Void)?

    private weak var pipeline: ImagePipeline?

    deinit {
        self._isCancelled.deallocate()
        #if TRACK_ALLOCATIONS
        Allocations.decrement("ImageTask")
        #endif
    }

    init(taskId: Int64, request: ImageRequest, isDataTask: Bool, pipeline: ImagePipeline) {
        self.taskId = taskId
        self.request = request
        self._priority = request.priority
        self.isDataTask = isDataTask
        self.pipeline = pipeline

        self._isCancelled = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        self._isCancelled.initialize(to: 0)

        #if TRACK_ALLOCATIONS
        Allocations.increment("ImageTask")
        #endif
    }

    /// Marks task as being cancelled.
    ///
    /// The pipeline will immediately cancel any work associated with a task
    /// unless there is an equivalent outstanding task running (see
    /// `ImagePipeline.Configuration.isCoalescingEnabled` for more info).
    public func cancel() {
        if OSAtomicCompareAndSwap32Barrier(0, 1, _isCancelled) {
            pipeline?.imageTaskCancelCalled(self)
        }
    }

    func setProgress(_ progress: TaskProgress) {
        completedUnitCount = progress.completed
        totalUnitCount = progress.total
        _progress?.completedUnitCount = progress.completed
        _progress?.totalUnitCount = progress.total
    }

    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self).hashValue)
    }

    public static func == (lhs: ImageTask, rhs: ImageTask) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    // MARK: CustomStringConvertible

    public var description: String {
        "ImageTask(id: \(taskId), priority: \(_priority), completedUnitCount: \(completedUnitCount), totalUnitCount: \(totalUnitCount), isCancelled: \(isCancelled))"
    }
}

/// A protocol that defines methods that image pipeline instances call on their
/// delegates to handle task-level events.
public protocol ImageTaskDelegate: AnyObject {
    /// Gets called when the task is started. The caller can save the instance
    /// of the class to update the task later.
    func imageTaskWillStart(_ task: ImageTask)

    /// Gets called when the progress is updated.
    func imageTask(_ task: ImageTask, didUpdateProgress progress: (completed: Int64, total: Int64))

    /// Gets called when a new progressive image is produced.
    func imageTask(_ task: ImageTask, didProduceProgressiveResponse response: ImageResponse)

    func imageTaskDidCancel(_ task: ImageTask)

    func imageTask(_ task: ImageTask, didCompleteWithResult result: Result<ImageResponse, ImagePipeline.Error>)

    func dataTask(_ task: ImageTask, didCompleteWithResult result: Result<(data: Data, response: URLResponse?), ImagePipeline.Error>)
}

extension ImageTaskDelegate {
    func imageTaskWillStart(_ task: ImageTask) {
        // Do nothing
    }

    func imageTask(_ task: ImageTask, didUpdateProgress progress: (completed: Int64, total: Int64)) {
        // Do nothing
    }

    func imageTask(_ task: ImageTask, didProduceProgressiveResponse response: ImageResponse) {
        // Do nothing
    }

    func imageTaskDidCancel(_ task: ImageTask) {
        // Do nothing
    }

    func imageTask(_ task: ImageTask, didCompleteWithResult result: Result<ImageResponse, ImagePipeline.Error>) {
        // Do nothing
    }

    func dataTask(_ task: ImageTask, didCompleteWithResult result: Result<(data: Data, response: URLResponse?), ImagePipeline.Error>) {
        // Do nothing
    }
}
