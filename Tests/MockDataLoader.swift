// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

private let fixture: Data = Test.data(name: "fixture", extension: "jpeg")

class MockDataLoader: DataLoading, @unchecked Sendable {
    static let DidStartTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidStartTask")
    static let DidCancelTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidCancelTask")

    var createdTaskCount = 0
    var results = [URL: Result<(Data, URLResponse), NSError>]()
    let queue = OperationQueue()
    var isSuspended: Bool {
        get { queue.isSuspended }
        set { queue.isSuspended = newValue }
    }

    func data(for request: URLRequest) -> AsyncThrowingStream<DataTaskSequenceElement, Error> {
        NotificationCenter.default.post(name: MockDataLoader.DidStartTask, object: self)
        createdTaskCount += 1

        return AsyncThrowingStream { [self] continuation in
            let operation = BlockOperation {
                if let result = self.results[request.url!] {
                    switch result {
                    case let .success(val):
                        let data = val.0
                        if !data.isEmpty {
                            continuation.yield(.respone(val.1))
                            continuation.yield(.data(data.prefix(data.count / 2)))
                            continuation.yield(.data(data.suffix(data.count / 2)))
                        }
                        continuation.finish()
                    case let .failure(err):
                        continuation.finish(throwing: err)
                    }
                } else {
                    continuation.yield(.respone(URLResponse(url: request.url ?? Test.url, mimeType: "jpeg", expectedContentLength: 22789, textEncodingName: nil)))
                    continuation.yield(.data(fixture))
                    continuation.finish()
                }
            }
            queue.addOperation(operation)
            continuation.onTermination = {
                guard case .cancelled = $0 else { return }
                NotificationCenter.default.post(name: MockDataLoader.DidCancelTask, object: self)
                operation.cancel()
            }
        }
    }
}
