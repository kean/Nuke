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

class MockImageTask: ImageTask {
    fileprivate var _cancel: () -> Void = {}

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

    override func loadImage(with request: Request, completion: @escaping (Result<Image>) -> Void) -> ImageTask {
        let task = MockImageTask()

        NotificationCenter.default.post(name: MockImagePipeline.DidStartTask, object: self)
        
        createdTaskCount += 1
        
        let operation = BlockOperation() {
            DispatchQueue.main.async {
                if let result = self.results[request.urlRequest.url!] {
                    completion(result)
                } else {
                    completion(.success(image))
                }
            }
        }
        queue.addOperation(operation)
        
        if !ignoreCancellation {
            task._cancel = {
                operation.cancel()
                NotificationCenter.default.post(name: MockImagePipeline.DidCancelTask, object: self)
            }
        }

        return task
    }

    override func cachedImage(for request: Request) -> Image? {
        return nil
    }
}
