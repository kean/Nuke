// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
@testable import Nuke

private class MockImageTask: ImageTask {
    fileprivate var onCancel: () -> Void = {}
    var __isCancelled = false

    init(request: ImageRequest) {
        super.init(taskId: 0, request: request, isDataTask: false)
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
    let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    override func loadImage(with request: ImageRequestConvertible,
                            queue callbackQueue: DispatchQueue? = nil,
                            progress progressHandler: ((_ intermediateResponse: ImageResponse?, _ completedUnitCount: Int64, _ totalUnitCount: Int64) -> Void)? = nil,
                            completion: ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil) -> ImageTask {
        let task = MockImageTask(request: request.asImageRequest())

        createdTaskCount += 1

        NotificationCenter.default.post(name: MockImagePipeline.DidStartTask, object: self)

        let operation = BlockOperation {
            for (completed, total) in [(10, 20), (20, 20)] as [(Int64, Int64)] {
                DispatchQueue.main.async {
                    if !task.__isCancelled {
                        task.completedUnitCount = completed
                        task.totalUnitCount = total
                        progressHandler?(nil, completed, total)
                    }
                }
            }

            DispatchQueue.main.async {
                if !task.__isCancelled {
                    completion?(.success(Test.response))
                }
                _ = task // Retain task
                NotificationCenter.default.post(name: MockImagePipeline.DidFinishTask, object: self)
            }
        }
        self.operationQueue.addOperation(operation)

        if isCancellationEnabled {
            task.onCancel = { [weak operation] in
                operation?.cancel()
                NotificationCenter.default.post(name: MockImagePipeline.DidCancelTask, object: self)
            }
        }

        return task
    }

    override func loadImage(with request: ImageRequest,
                            isConfined: Bool,
                            queue callbackQueue: DispatchQueue?,
                            progress progressHandler: ((_ intermediateResponse: ImageResponse?, _ completedUnitCount: Int64, _ totalUnitCount: Int64) -> Void)?,
                            completion: ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)?) -> ImageTask {
        self.loadImage(with: request, queue: callbackQueue, progress: progressHandler, completion: completion)
    }
}
