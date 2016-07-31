// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockDataLoader: DataLoading {
    static let DidStartTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidStartTask")
    static let DidCancelTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidCancelTask")
    
    var createdTaskCount = 0
    var results = [URL: Result<(Data, URLResponse), AnyError>]()
    let queue = OperationQueue()

    func loadData(with request: URLRequest, token: CancellationToken?) -> Promise<(Data, URLResponse)> {
        return Promise() { fulfill, reject in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: MockDataLoader.DidStartTask, object: self)
            }
            token?.register {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: MockDataLoader.DidCancelTask, object: self)
                }
            }
            
            createdTaskCount += 1
            
            queue.addOperation {
                let bundle = Bundle(for: MockDataLoader.self)
                let URL = bundle.urlForResource("Image", withExtension: "jpg")
                let data = try! Data(contentsOf: URL!)
                DispatchQueue.main.async {
                    if let result = self.results[request.url!] {
                        switch result {
                        case let .success(val): fulfill(value: val)
                        case let .failure(err): reject(error: err)
                        }
                    } else {
                        fulfill(value: (data, URLResponse()))
                    }
                }
            }
        }
    }
}
