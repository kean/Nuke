// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation
@testable import Nuke

private let image: Image = {
    let bundle = Bundle(for: MockImagePipeline.self)
    let URL = bundle.url(forResource: "Image", withExtension: "jpg")
    let data = try! Data(contentsOf: URL!)
    return Nuke.DataDecoder().decode(data: data, response: URLResponse())!
}()

private class _MockImageTask: ImageTask {
    fileprivate var _resume: () -> Void = {}
    fileprivate var _cancel: () -> Void = {}

    override init(request: ImageRequest, pipeline: ImagePipeline) {
        super.init(request: request, pipeline: pipeline)
    }

    override func resume() {
        _resume()
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
    var results = [URL: Result<Image>]()
    var ignoreCancellation = false

    override init(configuration: ImagePipeline.Configuration = ImagePipeline.Configuration()) {
        var conf = configuration
        conf.imageCache = nil // Disabla caching
        super.init(configuration: conf)
    }

    override func loadImage(with request: ImageRequest, completion: @escaping ImageTask.Completion) -> ImageTask {
        let task = _imageTask(with: request, completion)
        task.resume()
        return task
    }

    override func imageTask(with request: ImageRequest) -> ImageTask {
        return _imageTask(with: request)
    }

    private func _imageTask(with request: ImageRequest, _ completion: ImageTask.Completion? = nil) -> ImageTask {
        let task = _MockImageTask(request: request, pipeline: self)

        NotificationCenter.default.post(name: MockImagePipeline.DidStartTask, object: self)

        createdTaskCount += 1

        task._resume = {
            let operation = BlockOperation() {
                DispatchQueue.main.async {
                    let result = self.results[request.urlRequest.url!] ?? .success(image)

                    task.delegate?.imageTask(task, didFinishWithResult: result)
                    completion?(result)
                }
            }
            self.queue.addOperation(operation)

            if !self.ignoreCancellation {
                task._cancel = {
                    operation.cancel()
                    NotificationCenter.default.post(name: MockImagePipeline.DidCancelTask, object: self)
                }
            }
        }

        return task
    }
}
