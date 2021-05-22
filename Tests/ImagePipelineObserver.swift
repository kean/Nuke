// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

final class ImagePipelineObserver: ImagePipelineDelegate {
    var startedTaskCount = 0
    var cancelledTaskCount = 0
    var completedTaskCount = 0

    var events = [ImageTaskEvent]()

    static let didStartTask = Notification.Name("com.github.kean.Nuke.Tests.ImagePipelineObserver.DidStartTask")
    static let didCancelTask = Notification.Name("com.github.kean.Nuke.Tests.ImagePipelineObserver.DidCancelTask")
    static let didCompleteTask = Notification.Name("com.github.kean.Nuke.Tests.ImagePipelineObserver.DidFinishTask")

    static let taskKey = "taskKey"
    static let resultKey = "resultKey"

    func pipeline(_ pipeline: ImagePipeline, imageTask: ImageTask, didReceiveEvent event: ImageTaskEvent) {
        switch event {
        case .started:
            startedTaskCount += 1
            NotificationCenter.default.post(name: ImagePipelineObserver.didStartTask, object: self, userInfo: [ImagePipelineObserver.taskKey: imageTask])
        case .cancelled:
            cancelledTaskCount += 1
            NotificationCenter.default.post(name: ImagePipelineObserver.didCancelTask, object: self, userInfo: [ImagePipelineObserver.taskKey: imageTask])
        case .completed(let result):
            completedTaskCount += 1
            NotificationCenter.default.post(name: ImagePipelineObserver.didCompleteTask, object: self, userInfo: [ImagePipelineObserver.taskKey: imageTask, ImagePipelineObserver.resultKey: result])
        default:
            break
        }
        events.append(event)
    }
}
