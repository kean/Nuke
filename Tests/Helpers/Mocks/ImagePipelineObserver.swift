// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

final class ImagePipelineObserver: ImagePipeline.Delegate, @unchecked Sendable {
    var createdTaskCount = 0
    var cancelledTaskCount = 0
    var completedTaskCount = 0

    static let didCreateTask = Notification.Name("com.github.kean.Nuke.Tests.ImagePipelineObserver.didCreateTask")
    static let didCancelTask = Notification.Name("com.github.kean.Nuke.Tests.ImagePipelineObserver.DidCancelTask")
    static let didCompleteTask = Notification.Name("com.github.kean.Nuke.Tests.ImagePipelineObserver.DidFinishTask")

    static let taskKey = "taskKey"
    static let resultKey = "resultKey"

    var events = [ImageTask.Event]()

    private let lock = NSLock()

    private func append(_ event: ImageTask.Event) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func imageTaskCreated(_ task: ImageTask, pipeline: ImagePipeline) {
        createdTaskCount += 1
        NotificationCenter.default.post(name: ImagePipelineObserver.didCreateTask, object: self, userInfo: [ImagePipelineObserver.taskKey: task])
    }

    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        append(event)

        switch event {
        case .finished(let result):
            if case .failure(.cancelled) = result {
                cancelledTaskCount += 1
                NotificationCenter.default.post(name: ImagePipelineObserver.didCancelTask, object: self, userInfo: [ImagePipelineObserver.taskKey: task])
            } else {
                completedTaskCount += 1
                NotificationCenter.default.post(name: ImagePipelineObserver.didCompleteTask, object: self, userInfo: [ImagePipelineObserver.taskKey: task, ImagePipelineObserver.resultKey: result])
            }
        default:
            break
        }
    }
}

extension ImageTask.Event: @retroactive Equatable {
    public static func == (lhs: ImageTask.Event, rhs: ImageTask.Event) -> Bool {
        switch (lhs, rhs) {
        case let (.progress(lhs), .progress(rhs)): lhs == rhs
        case let (.preview(lhs), .preview(rhs)): lhs == rhs
        case let (.finished(lhs), .finished(rhs)): lhs == rhs
        default: false
        }
    }
}
