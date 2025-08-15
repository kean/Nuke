// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

private let data: Data = Test.data(name: "fixture", extension: "jpeg")

private final class MockDataTask: MockDataTaskProtocol, @unchecked Sendable {
    var _cancel: () -> Void = { }
    func cancel() {
        _cancel()
    }
}

class MockDataLoader: MockDataLoading, DataLoading, @unchecked Sendable {
    static let DidStartTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidStartTask")
    static let DidCancelTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidCancelTask")

    @Mutex var createdTaskCount = 0
    var results = [URL: Result<(Data, URLResponse), NSError>]()
    let queue = OperationQueue()
    var isSuspended: Bool {
        get { queue.isSuspended }
        set { queue.isSuspended = newValue }
    }

    func loadData(with request: URLRequest, didReceiveData: @Sendable @escaping (Data, URLResponse) -> Void, completion: @Sendable @escaping (Error?) -> Void) -> MockDataTaskProtocol {
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

// Remove these and update to implement the actual protocol.
protocol MockDataLoading: DataLoading {
    func loadData(with request: URLRequest, didReceiveData: @Sendable @escaping (Data, URLResponse) -> Void, completion: @Sendable @escaping (Error?) -> Void) -> MockDataTaskProtocol
}

extension MockDataLoading where Self: DataLoading {
    func loadData(for request: URLRequest) -> AsyncThrowingStream<(Data, URLResponse), any Error> {
        AsyncThrowingStream { continuation in
            let task = loadData(with: request) { data, response in
                continuation.yield((data, response))
            } completion: { error in
                continuation.finish(throwing: error)
            }
            continuation.onTermination = { reason in
                switch reason {
                case .cancelled: task.cancel()
                default: break
                }
            }
        }
    }
}

protocol MockDataTaskProtocol: Sendable {
    func cancel()
}

