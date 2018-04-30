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
    
    var createdTaskCount = 0
    let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    var perform: (_ task: ImageTask) -> Void = { task in
        DispatchQueue.main.async {
            task.completion?(Test.response, nil)
        }
    }

    override init(configuration: ImagePipeline.Configuration = ImagePipeline.Configuration()) {
        var conf = configuration
        conf.imageCache = nil // Disabla caching
        super.init(configuration: conf)
    }

    override func loadImage(with request: ImageRequest, completion: @escaping ImageTask.Completion) -> ImageTask {
        let task = _MockImageTask(request: request)
        task.completion = completion

        NotificationCenter.default.post(name: MockImagePipeline.DidStartTask, object: self)
        
        createdTaskCount += 1
        
        let operation = BlockOperation() { [weak self] in
            self?.perform(task)
        }
        self.queue.addOperation(operation)
        
        task._cancel = {
            operation.cancel()
            NotificationCenter.default.post(name: MockImagePipeline.DidCancelTask, object: self)
        }

        return task
    }
}
