// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

public final class ImagePipelineObserver: ImagePipelineDelegate, @unchecked Sendable {
    public var startedTaskCount = 0
    public var cancelledTaskCount = 0
    public var completedTaskCount = 0

    public static let didStartTask = Notification.Name("com.github.kean.Nuke.Tests.ImagePipelineObserver.DidStartTask")
    public static let didCancelTask = Notification.Name("com.github.kean.Nuke.Tests.ImagePipelineObserver.DidCancelTask")
    public static let didCompleteTask = Notification.Name("com.github.kean.Nuke.Tests.ImagePipelineObserver.DidFinishTask")

    static let taskKey = "taskKey"
    static let resultKey = "resultKey"

    public var events = [ImageTaskEvent]()

    public var onTaskCreated: ((ImageTask) -> Void)?

    private let lock = NSLock()

    public init() {}

    private func append(_ event: ImageTaskEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    public func imageTaskCreated(_ task: ImageTask, pipeline: ImagePipeline) {
        onTaskCreated?(task)
        append(.created)
    }

    public func imageTaskDidStart(_ task: ImageTask, pipeline: ImagePipeline) {
        startedTaskCount += 1
        NotificationCenter.default.post(name: ImagePipelineObserver.didStartTask, object: self, userInfo: [ImagePipelineObserver.taskKey: task])
        append(.started)
    }

    public func imageTaskDidCancel(_ task: ImageTask, pipeline: ImagePipeline) {
        append(.cancelled)

        cancelledTaskCount += 1
        NotificationCenter.default.post(name: ImagePipelineObserver.didCancelTask, object: self, userInfo: [ImagePipelineObserver.taskKey: task])
    }

    public func imageTask(_ task: ImageTask, didUpdateProgress progress: ImageTask.Progress, pipeline: ImagePipeline) {
        append(.progressUpdated(completedUnitCount: progress.completed, totalUnitCount: progress.total))
    }

    public func imageTask(_ task: ImageTask, didReceivePreview response: ImageResponse, pipeline: ImagePipeline) {
        append(.intermediateResponseReceived(response: response))
    }

    public func imageTask(_ task: ImageTask, didCompleteWithResult result: Result<ImageResponse, ImagePipeline.Error>, pipeline: ImagePipeline) {
        append(.completed(result: result))

        completedTaskCount += 1
        NotificationCenter.default.post(name: ImagePipelineObserver.didCompleteTask, object: self, userInfo: [ImagePipelineObserver.taskKey: task, ImagePipelineObserver.resultKey: result])
    }
}

public enum ImageTaskEvent: Equatable {
    case created
    case started
    case cancelled
    case intermediateResponseReceived(response: ImageResponse)
    case progressUpdated(completedUnitCount: Int64, totalUnitCount: Int64)
    case completed(result: Result<ImageResponse, ImagePipeline.Error>)

    public static func == (lhs: ImageTaskEvent, rhs: ImageTaskEvent) -> Bool {
        switch (lhs, rhs) {
        case (.created, .created): return true
        case (.started, .started): return true
        case (.cancelled, .cancelled): return true
        case let (.intermediateResponseReceived(lhs), .intermediateResponseReceived(rhs)): return lhs == rhs
        case let (.progressUpdated(lhsTotal, lhsCompleted), .progressUpdated(rhsTotal, rhsCompleted)):
            return (lhsTotal, lhsCompleted) == (rhsTotal, rhsCompleted)
        case let (.completed(lhs), .completed(rhs)): return lhs == rhs
        default: return false
        }
    }
}
