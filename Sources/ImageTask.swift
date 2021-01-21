// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

#if !os(macOS)
import UIKit.UIImage
#else
import AppKit.NSImage
#endif

// MARK: - ImageTask

/// A task performed by the `ImagePipeline`. The pipeline maintains a strong
/// reference to the task until the request finishes or fails; you do not need
/// to maintain a reference to the task unless it is useful to do so for your
/// app’s internal bookkeeping purposes.
public /* final */ class ImageTask: Hashable, CustomStringConvertible {
    /// An identifier that uniquely identifies the task within a given pipeline. Only
    /// unique within that pipeline.
    public let taskId: Int

    let isDataTask: Bool

    weak var pipeline: ImagePipeline?

    /// The original request with which the task was created.
    public let request: ImageRequest

    /// Updates the priority of the task, even if the task is already running.
    public var priority: ImageRequest.Priority {
        didSet {
            pipeline?.imageTaskUpdatePriorityCalled(self, priority: priority)
        }
    }
    var _priority: ImageRequest.Priority // Backing store for access from pipeline

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

    var isCancelled: Bool {
        lock?.lock()
        defer { lock?.unlock() }
        return _isCancelled
    }
    private(set) var _isCancelled = false
    private let lock: NSLock?

    /// A completion handler to be called when task finishes or fails.
    public typealias Completion = (_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void

    /// A progress handler to be called periodically during the lifetime of a task.
    public typealias ProgressHandler = (_ intermediateResponse: ImageResponse?, _ completedUnitCount: Int64, _ totalUnitCount: Int64) -> Void

    #if TRACK_ALLOCATIONS
    deinit {
        Allocations.decrement("ImageTask")
    }
    #endif

    init(taskId: Int, request: ImageRequest, isMainThreadConfined: Bool = false, isDataTask: Bool) {
        self.taskId = taskId
        self.request = request
        self._priority = request.priority
        self.priority = request.priority
        self.isDataTask = isDataTask
        lock = isMainThreadConfined ? nil : NSLock()

        #if TRACK_ALLOCATIONS
        Allocations.increment("ImageTask")
        #endif
    }

    /// Marks task as being cancelled.
    ///
    /// The pipeline will immediately cancel any work associated with a task
    /// unless there is an equivalent outstanding task running (see
    /// `ImagePipeline.Configuration.isDeduplicationEnabled` for more info).
    public func cancel() {
        if let lock = lock {
            lock.lock()
            defer { lock.unlock() }
            _cancel()
        } else {
            assert(Thread.isMainThread, "Must be cancelled only from the main thread")
            _cancel()
        }
    }

    private func _cancel() {
        if !_isCancelled {
            _isCancelled = true
            pipeline?.imageTaskCancelCalled(self)
        }
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
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        "ImageTask(id: \(taskId), priority: \(priority), completedUnitCount: \(completedUnitCount), totalUnitCount: \(totalUnitCount), isCancelled: \(isCancelled))"
    }
}

// MARK: - ImageContainer

public struct ImageContainer {
    public var image: PlatformImage
    public var type: ImageType?
    /// Returns `true` if the image in the container is a preview of the image.
    public var isPreview: Bool
    /// Contains the original image `data`, but only if the decoder decides to
    /// attach it to the image.
    ///
    /// The default decoder (`ImageDecoders.Default`) attaches data to GIFs to
    /// allow to display them using a rendering engine of your choice.
    ///
    /// - note: The `data`, along with the image container itself gets stored in the memory
    /// cache.
    public var data: Data?
    public var userInfo: [AnyHashable: Any]

    public init(image: PlatformImage, type: ImageType? = nil, isPreview: Bool = false, data: Data? = nil, userInfo: [AnyHashable: Any] = [:]) {
        self.image = image
        self.type = type
        self.isPreview = isPreview
        self.data = data
        self.userInfo = userInfo
    }

    /// Modifies the wrapped image and keeps all of the rest of the metadata.
    public func map(_ closure: (PlatformImage) -> PlatformImage?) -> ImageContainer? {
        guard let image = closure(self.image) else {
            return nil
        }
        return ImageContainer(image: image, type: type, isPreview: isPreview, data: data, userInfo: userInfo)
    }
}

// MARK: - ImageResponse

/// Represents a response of a particular image task.
public final class ImageResponse {
    public let container: ImageContainer
    /// A convenience computed property which returns an image from the container.
    public var image: PlatformImage { container.image }
    public let urlResponse: URLResponse?

    // the response is only nil when new disk cache is enabled (it only stores
    // data for now, but this might change in the future).
    @available(*, deprecated, message: "Please use `container.userInfo[ImageDecoders.Default.scanNumberKey]` instead.") // Deprecated in Nuke 9.0
    public var scanNumber: Int? {
        if let number = _scanNumber {
            return number // Deprecated version
        }
        return container.userInfo[ImageDecoders.Default.scanNumberKey] as? Int
    }

    private let _scanNumber: Int?

    @available(*, deprecated, message: "Please use `ImageResponse.init(container:urlResponse:)` instead.") // Deprecated in Nuke 9.0
    public init(image: PlatformImage, urlResponse: URLResponse? = nil, scanNumber: Int? = nil) {
        self.container = ImageContainer(image: image)
        self.urlResponse = urlResponse
        self._scanNumber = scanNumber
    }

    public init(container: ImageContainer, urlResponse: URLResponse? = nil) {
        self.container = container
        self.urlResponse = urlResponse
        self._scanNumber = nil
    }

    func map(_ transformation: (ImageContainer) -> ImageContainer?) -> ImageResponse? {
        return autoreleasepool {
            guard let output = transformation(container) else {
                return nil
            }
            return ImageResponse(container: output, urlResponse: urlResponse)
        }
    }
}
