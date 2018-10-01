// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation
@testable import Nuke

private class _MockImageTask: ImageTask {
    fileprivate var _cancel: () -> Void = {}

    init(request: ImageRequest) {
        super.init(taskId: 0, request: request)
    }

    override func cancel() {
        _cancel()
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

    @discardableResult
    override func loadImage(with request: ImageRequest, progress: ImageTask.ProgressHandler? = nil, completion: ImageTask.Completion? = nil) -> ImageTask {
        let task = _MockImageTask(request: request)

        createdTaskCount += 1

        NotificationCenter.default.post(name: MockImagePipeline.DidStartTask, object: self)

        let operation = BlockOperation {
            for (completed, total) in [(10, 20), (20, 20)] as [(Int64, Int64)] {
                DispatchQueue.main.async {
                    progress?(nil, completed, total)
                }
            }

            DispatchQueue.main.async {
                completion?(Test.response, nil)
                _ = task // Retain task
                NotificationCenter.default.post(name: MockImagePipeline.DidFinishTask, object: self)
            }
        }
        self.queue.addOperation(operation)

        if isCancellationEnabled {
            task._cancel = { [weak operation] in
                operation?.cancel()
                NotificationCenter.default.post(name: MockImagePipeline.DidCancelTask, object: self)
            }
        }

        return task
    }
}
