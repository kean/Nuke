// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation
@testable import Nuke

private class MockImageTask: ImageTask {
    fileprivate var onStart: () -> Void = {}
    fileprivate var isCancelled = false
    fileprivate var onCancel: () -> Void = {}

    init(request: ImageRequest) {
        super.init(taskId: 0, request: request)
    }

    override func start() {
        onStart()
    }

    override func cancel() {
        isCancelled = true
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

    @discardableResult
    override func loadImage(with request: ImageRequest, progress: ImageTask.ProgressHandler? = nil, completion: ImageTask.Completion? = nil) -> ImageTask {
        let task = MockImageTask(request: request)
        let delegate = MockImageTaskDelegate()
        delegate.progressHandler = { progress?($0, $1) }
        delegate.completion = completion
        loadImage(for: task, delegate: delegate, anonymous: delegate)
        return task
    }

    override func imageTask(with request: ImageRequest, delegate: ImageTaskDelegate) -> ImageTask {
        let task = MockImageTask(request: request)
        task.onStart = { [weak self, weak delegate] in
            guard let self = self, let delegate = delegate else { return }
            self.loadImage(for: task, delegate: delegate)
        }
        return task
    }

    private func loadImage(for task: MockImageTask, delegate: ImageTaskDelegate, anonymous: MockImageTaskDelegate? = nil) {
        createdTaskCount += 1

        NotificationCenter.default.post(name: MockImagePipeline.DidStartTask, object: self)

        let operation = BlockOperation { [weak delegate] in
            for (completed, total) in [(10, 20), (20, 20)] as [(Int64, Int64)] {
                DispatchQueue.main.async {
                    guard !task.isCancelled else { return }
                    delegate?.imageTask(task, didUpdateProgress: completed, totalUnitCount: total)
                    _ = anonymous // retain the delegates
                }
            }

            DispatchQueue.main.async {
                _ = task // Retain task
                NotificationCenter.default.post(name: MockImagePipeline.DidFinishTask, object: self)

                guard !task.isCancelled else { return }
                delegate?.imageTask(task, didCompleteWithResponse: Test.response, error: nil)
                _ = anonymous // retain the delegates
            }
        }

        if isCancellationEnabled {
            task.onCancel = { [weak operation] in
                operation?.cancel()
                NotificationCenter.default.post(name: MockImagePipeline.DidCancelTask, object: self)
            }
        }

        self.queue.addOperation(operation)
    }
}

final class MockImageTaskDelegate: ImageTaskDelegate {
    var progressHandler: ((_ total: Int64, _ completed: Int64) -> Void)?
    var progressiveResponseHandler: ((ImageResponse) -> Void)?
    var completion: ((ImageResponse?, ImagePipeline.Error?) -> Void)?
    var next: ImageTaskDelegate?

    func imageTask(_ task: ImageTask, didUpdateProgress completedUnitCount: Int64, totalUnitCount: Int64) {
        progressHandler?(completedUnitCount, totalUnitCount)
        next?.imageTask(task, didUpdateProgress: completedUnitCount, totalUnitCount: totalUnitCount)
    }

    func imageTask(_ task: ImageTask, didProduceProgressiveResponse response: ImageResponse) {
        progressiveResponseHandler?(response)
        next?.imageTask(task, didProduceProgressiveResponse: response)
    }

    func imageTask(_ task: ImageTask, didCompleteWithResponse response: ImageResponse?, error: ImagePipeline.Error?) {
        completion?(response, error)
        next?.imageTask(task, didCompleteWithResponse: response, error: error)
    }
}
