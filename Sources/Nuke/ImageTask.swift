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
    public let taskId: Int64

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

    var isCancelled: Bool { _isCancelled.pointee == 1 }
    private let _isCancelled: UnsafeMutablePointer<Int32>

    deinit {
        self._isCancelled.deallocate()
        #if TRACK_ALLOCATIONS
        Allocations.decrement("ImageTask")
        #endif
    }

    init(taskId: Int64, request: ImageRequest, isDataTask: Bool) {
        self.taskId = taskId
        self.request = request
        self._priority = request.priority
        self.priority = request.priority
        self.isDataTask = isDataTask

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
    /// Contains a cache type in case the image was returned from one of the
    /// pipeline caches (not including any of the HTTP caches if enabled).
    public let cacheType: CacheType?

    public init(container: ImageContainer, urlResponse: URLResponse? = nil, cacheType: CacheType? = nil) {
        self.container = container
        self.urlResponse = urlResponse
        self.cacheType = cacheType
    }

    func map(_ transformation: (ImageContainer) -> ImageContainer?) -> ImageResponse? {
        return autoreleasepool {
            guard let output = transformation(container) else {
                return nil
            }
            return ImageResponse(container: output, urlResponse: urlResponse, cacheType: cacheType)
        }
    }

    public enum CacheType {
        case memory
        case disk
    }
}

// MARK: - Misc

#if !os(macOS)
import UIKit.UIImage
import UIKit.UIColor
/// Alias for `UIImage`.
public typealias PlatformImage = UIImage
#else
import AppKit.NSImage
/// Alias for `NSImage`.
public typealias PlatformImage = NSImage
#endif
