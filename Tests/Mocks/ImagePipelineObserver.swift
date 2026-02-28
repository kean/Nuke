// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

final class ImagePipelineObserver: ImagePipelineDelegate, @unchecked Sendable {
    var startedTaskCount = 0
    var cancelledTaskCount = 0
    var completedTaskCount = 0

    static let didStartTask = Notification.Name("com.github.kean.Nuke.Tests.ImagePipelineObserver.DidStartTask")
    static let didCancelTask = Notification.Name("com.github.kean.Nuke.Tests.ImagePipelineObserver.DidCancelTask")
    static let didCompleteTask = Notification.Name("com.github.kean.Nuke.Tests.ImagePipelineObserver.DidFinishTask")

    static let taskKey = "taskKey"
    static let resultKey = "resultKey"

    var events = [ImageTaskEvent]()

    var onTaskCreated: ((ImageTask) -> Void)?

    private let lock = NSLock()

    private func append(_ event: ImageTaskEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func imageTaskCreated(_ task: ImageTask, pipeline: ImagePipeline) {
        onTaskCreated?(task)
        append(.created)
    }

    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        switch event {
        case .started:
            startedTaskCount += 1
            NotificationCenter.default.post(name: ImagePipelineObserver.didStartTask, object: self, userInfo: [ImagePipelineObserver.taskKey: task])
            append(.started)
        case .progress(let progress):
            append(.progressUpdated(completedUnitCount: progress.completed, totalUnitCount: progress.total))
        case .preview(let response):
            append(.intermediateResponseReceived(response: response))
        case .cancelled:
            cancelledTaskCount += 1
            NotificationCenter.default.post(name: ImagePipelineObserver.didCancelTask, object: self, userInfo: [ImagePipelineObserver.taskKey: task])
            append(.cancelled)
        case .finished(let result):
            completedTaskCount += 1
            NotificationCenter.default.post(name: ImagePipelineObserver.didCompleteTask, object: self, userInfo: [ImagePipelineObserver.taskKey: task, ImagePipelineObserver.resultKey: result])
            append(.completed(result: result))
        }
    }
}

enum ImageTaskEvent: Equatable {
    case created
    case started
    case cancelled
    case intermediateResponseReceived(response: ImageResponse)
    case progressUpdated(completedUnitCount: Int64, totalUnitCount: Int64)
    case completed(result: Result<ImageResponse, ImagePipeline.Error>)

    static func == (lhs: ImageTaskEvent, rhs: ImageTaskEvent) -> Bool {
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
