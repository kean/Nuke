// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

private let data: Data = {
    let bundle = Bundle(for: MockDataLoader.self)
    let URL = bundle.url(forResource: "Image", withExtension: "jpg")
    return try! Data(contentsOf: URL!)
}()

class MockDataLoader: DataLoading {
    static let DidStartTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidStartTask")
    static let DidCancelTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidCancelTask")
    
    var createdTaskCount = 0
    var results = [URL: Result<(Data, URLResponse)>]()
    let queue = OperationQueue()

    func loadData(with request: Request, token: CancellationToken?, completion: @escaping (Result<(Data, URLResponse)>) -> Void) {
        NotificationCenter.default.post(name: MockDataLoader.DidStartTask, object: self)
        token?.register {
            NotificationCenter.default.post(name: MockDataLoader.DidCancelTask, object: self)
        }
        
        createdTaskCount += 1
        
        let operation = BlockOperation() {
            if let result = self.results[request.urlRequest.url!] {
                completion(result)
            } else {
                completion(.success((data, URLResponse())))
            }
        }
        queue.addOperation(operation)
        
        token?.register {
            operation.cancel()
        }
    }
}
