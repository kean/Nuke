// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

private let image: Image = {
    let bundle = Bundle(for: MockImageLoader.self)
    let URL = bundle.url(forResource: "Image", withExtension: "jpg")
    let data = try! Data(contentsOf: URL!)
    return Nuke.DataDecoder().decode(data: data, response: URLResponse())!
}()

class MockImageLoader: Loading {
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

    func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        NotificationCenter.default.post(name: MockImageLoader.DidStartTask, object: self)
        
        createdTaskCount += 1
        
        let operation = BlockOperation() {
            if let result = self.results[request.urlRequest.url!] {
                completion(result)
            } else {
                completion(.success(image))
            }
        }
        queue.addOperation(operation)
        
        if !ignoreCancellation {
            token?.register {
                operation.cancel()
                NotificationCenter.default.post(name: MockImageLoader.DidCancelTask, object: self)
            }
        }
    }
}
