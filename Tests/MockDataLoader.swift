// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

private let data: Data = Test.data(name: "fixture", extension: "jpeg")

private final class MockDataTask: Cancellable, @unchecked Sendable {
    var _cancel: () -> Void = { }
    func cancel() {
        _cancel()
    }
}

class MockDataLoader: DataLoading, @unchecked Sendable {
    static let DidStartTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidStartTask")
    static let DidCancelTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidCancelTask")

    @Atomic var createdTaskCount = 0
    var results = [URL: Result<(Data, URLResponse), NSError>]()
    let queue = OperationQueue()
    var isSuspended: Bool {
        get { queue.isSuspended }
        set { queue.isSuspended = newValue }
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> Cancellable {
        let task = MockDataTask()

        NotificationCenter.default.post(name: MockDataLoader.DidStartTask, object: self)

        createdTaskCount += 1

        let operation = BlockOperation {
            if let result = self.results[request.url!] {
                switch result {
                case let .success(val):
                    let data = val.0
                    if !data.isEmpty {
                        didReceiveData(data.prefix(data.count / 2), val.1)
                        didReceiveData(data.suffix(data.count / 2), val.1)
                    }
                    completion(nil)
                case let .failure(err):
                    completion(err)
                }
            } else {
                didReceiveData(data, URLResponse(url: request.url ?? Test.url, mimeType: "jpeg", expectedContentLength: 22789, textEncodingName: nil))
                completion(nil)
            }
        }
        queue.addOperation(operation)

        task._cancel = {
            NotificationCenter.default.post(name: MockDataLoader.DidCancelTask, object: self)
            operation.cancel()
        }

        return task
    }
}
