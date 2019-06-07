// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation
@testable import Nuke

private class MockImageTask: ImageTask {
    fileprivate var onCancel: () -> Void = {}
    var __isCancelled = false

    init(request: ImageRequest) {
        super.init(taskId: 0, request: request)
    }

    override func cancel() {
        __isCancelled = true
        onCancel()
    }
}

class MockImagePipeline: ImagePipeline {
    static let DidStartTask = Notification.Name("com.github.kean.Nuke.Tests.MockLoader.DidStartTask")
    static let DidCancelTask = Notification.Name("com.github.kean.Nuke.Tests.MockLoader.DidCancelTask")
    static let DidFinishTask = Notification.Name("com.github.kean.Nuke.Tests.MockLoader.DidFinishTask")

    var isCancellationEnabled = true

    var createdTaskCount = 0
    let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    override func loadImage(with request: ImageRequest, isMainThreadConfined: Bool, observer: @escaping (ImageTask, Task<ImageResponse, ImagePipeline.Error>.Event) -> Void) -> ImageTask {
        let task = MockImageTask(request: request)

        createdTaskCount += 1

        NotificationCenter.default.post(name: MockImagePipeline.DidStartTask, object: self)

        let operation = BlockOperation {
            for (completed, total) in [(10, 20), (20, 20)] as [(Int64, Int64)] {
                DispatchQueue.main.async {
                    if !task.__isCancelled {
                        task.completedUnitCount = completed
                        task.totalUnitCount = total
                        observer(task, .progress(TaskProgress(completed: completed, total: total)))
                    }
                }
            }

            DispatchQueue.main.async {
                if !task.__isCancelled {
                    observer(task, .value(Test.response, isCompleted: true))
                }
                _ = task // Retain task
                NotificationCenter.default.post(name: MockImagePipeline.DidFinishTask, object: self)
            }
        }
        self.queue.addOperation(operation)

        if isCancellationEnabled {
            task.onCancel = { [weak operation] in
                operation?.cancel()
                NotificationCenter.default.post(name: MockImagePipeline.DidCancelTask, object: self)
            }
        }

        return task
    }
}
