// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

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
    var results = [URL: PromiseResolution<Image>]()
    var ignoreCancellation = false

    func loadImage(with request: Request, token: CancellationToken?) -> Promise<Image> {
        return Promise() { fulfill, reject in
            NotificationCenter.default.post(name: MockImageLoader.DidStartTask, object: self)
            
            createdTaskCount += 1
            
            let operation = BlockOperation() {
                if let result = self.results[request.urlRequest.url!] {
                    switch result {
                    case let .fulfilled(val): fulfill(val)
                    case let .rejected(err): reject(err)
                    }
                } else {
                    fulfill(image)
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
}
