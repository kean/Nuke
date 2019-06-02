// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

private let data: Data = Test.data(name: "fixture", extension: "jpeg")

private final class MockDataTask: Cancellable {
    var _cancel: () -> Void = { }
    func cancel() {
        _cancel()
    }
}

class MockDataLoader: DataLoading {
    static let DidStartTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidStartTask")
    static let DidCancelTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidCancelTask")
    
    var createdTaskCount = 0
    var results = [URL: _Result<(Data, URLResponse), NSError>]()
    let queue = OperationQueue()

    func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) -> Cancellable {
        let task = MockDataTask()

        NotificationCenter.default.post(name: MockDataLoader.DidStartTask, object: self)

        createdTaskCount += 1

        let operation = BlockOperation {
            if let result = self.results[request.url!] {
                switch result {
                case let .success(val):
                    let data = val.0
                    assert(!data.isEmpty)
                    didReceiveData(data.prefix(data.count / 2), val.1)
                    didReceiveData(data.suffix(data.count / 2), val.1)
                    completion(nil)
                case let .failure(err):
                    completion(err)
                }
            } else {
                didReceiveData(data, URLResponse())
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

// MARK: - Result

// we're still using Result internally, but don't pollute user's space
enum _Result<T, Error: Swift.Error> {
    case success(T), failure(Error)

    /// Returns a `value` if the result is success.
    var value: T? {
        if case let .success(val) = self { return val } else { return nil }
    }

    /// Returns an `error` if the result is failure.
    var error: Error? {
        if case let .failure(err) = self { return err } else { return nil }
    }
}
