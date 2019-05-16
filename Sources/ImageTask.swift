// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageTaskDelegate

/// All methods of the delegates are called on the main thread.
public protocol ImageTaskDelegate: class {
    /// Called when the task finishes loading the image.
    func imageTask(_ task: ImageTask, didCompleteWithResult result: Result<ImageResponse, ImagePipeline.Error>)

    /// Called periodically during the lifetime of a task when progress is updated.
    func imageTask(_ task: ImageTask, didUpdateProgress completedUnitCount: Int64, totalUnitCount: Int64)

    /// Called periodically when new scans of progressive image are loaded and
    /// processed.
    ///
    /// To enable progressive image decoding, see `ImagePipeline.Configuration`
    /// `isProgressiveDecodingEnabled`.
    func imageTask(_ task: ImageTask, didProduceProgressiveResponse response: ImageResponse)
}

public extension ImageTaskDelegate {
    func imageTask(_ task: ImageTask, didUpdateProgress completedUnitCount: Int64, totalUnitCount: Int64) {}
    func imageTask(_ task: ImageTask, didProduceProgressiveResponse response: ImageResponse) {}
}

// MARK: - ImageTask

/// A task performed by the `ImagePipeline`. The pipeline maintains a strong
/// reference to the task until the request finishes or fails; you do not need
/// to maintain a reference to the task unless it is useful to do so for your
/// app’s internal bookkeeping purposes.
public /* final */ class ImageTask: Hashable {
    /// An identifier uniquely identifies the task within a given pipeline. Only
    /// unique within this pipeline.
    public let taskId: Int

    weak var delegate: ImageTaskDelegate?
    weak var pipeline: ImagePipeline?

    /// The original request with which the task was created.
    public let request: ImageRequest
    var priority: ImageRequest.Priority

    /// The number of bytes that the task has received.
    public internal(set) var completedUnitCount: Int64 = 0

    /// A best-guess upper bound on the number of bytes the client expects to send.
    public internal(set) var totalUnitCount: Int64 = 0

    /// Returns a progress object for the task. The object is created lazily.
    public var progress: Progress {
        if _progress == nil { _progress = Progress() }
        return _progress!
    }
    private(set) var _progress: Progress?

    /// A completion handler to be called when task finishes or fails.
    public typealias Completion = (_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void

    /// A progress handler to be called periodically during the lifetime of a task.
    public typealias ProgressHandler = (_ completedUnitCount: Int64, _ totalUnitCount: Int64) -> Void

    // internal stuff associated with a task
    var metrics: ImageTaskMetrics?

    // `true` is the task is ready to be started
    var isStartNeeded = true

    init(taskId: Int, request: ImageRequest) {
        self.taskId = taskId
        self.request = request
        self.priority = request.priority
    }

    /// Starts executing the task.
    public func start() {
        pipeline?.imageTaskStartCalled(self)
    }

    /// Marks task as being cancelled.
    ///
    /// The pipeline will immediately cancel any work associated with a task
    /// unless there is an equivalent outstanding task running (see
    /// `ImagePipeline.Configuration.isDeduplicationEnabled` for more info).
    public func cancel() {
        delegate = nil // Zeroing weak references is always thread-safe
        pipeline?.imageTaskCancelCalled(self)
        pipeline = nil // Zeroing weak references is always thread-safe
    }

    /// Update s priority of the task even if the task is already running.
    public func setPriority(_ priority: ImageRequest.Priority) {
        pipeline?.imageTaskUpdatePriorityCalled(self, priority: priority)
    }

    // MARK: - Internal

    func setProgress(_ progress: TaskProgress) {
        completedUnitCount = progress.completed
        totalUnitCount = progress.total
        _progress?.completedUnitCount = progress.completed
        _progress?.totalUnitCount = progress.total
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self).hashValue)
    }

    public static func == (lhs: ImageTask, rhs: ImageTask) -> Bool {
        return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}

// MARK: - ImageResponse

/// Represents an image response.
public final class ImageResponse {
    public let image: Image
    public let urlResponse: URLResponse?
    // the response is only nil when new disk cache is enabled (it only stores
    // data for now, but this might change in the future).
    public let scanNumber: Int?

    public init(image: Image, urlResponse: URLResponse? = nil, scanNumber: Int? = nil) {
        self.image = image
        self.urlResponse = urlResponse
        self.scanNumber = scanNumber
    }

    func map(_ transformation: (Image) -> Image?) -> ImageResponse? {
        return autoreleasepool {
            guard let output = transformation(image) else {
                return nil
            }
            return ImageResponse(image: output, urlResponse: urlResponse, scanNumber: scanNumber)
        }
    }
}

// MARK: - ImageTaskAnonymousDelegate

final class ImageTaskAnonymousDelegate: ImageTaskDelegate {
    let completionHandler: ImageTask.Completion?
    let progressHandler: ImageTask.ProgressHandler?

    init(progress: ImageTask.ProgressHandler?, completion: ImageTask.Completion?) {
        self.progressHandler = progress
        self.completionHandler = completion
    }

    func imageTask(_ task: ImageTask, didCompleteWithResult result: Result<ImageResponse, ImagePipeline.Error>) {
        completionHandler?(result)
    }

    func imageTask(_ task: ImageTask, didUpdateProgress completedUnitCount: Int64, totalUnitCount: Int64) {
        progressHandler?(completedUnitCount, totalUnitCount)
    }
}
