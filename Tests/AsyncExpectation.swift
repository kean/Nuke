import Foundation
import Combine
import Testing

final class AsyncExpectation: @unchecked Sendable {
    private var isFinished = false
    private var continuations: [UnsafeContinuation<Void, Never>] = []
    private let lock = NSLock()
    private var cancellables: [AnyCancellable] = []

    init(notification: Notification.Name, object: AnyObject) {
        NotificationCenter.default
            .publisher(for: notification, object: object)
            .sink { _ in
                self.fulfill()
            }
            .store(in: &cancellables)
    }

    func wait() async {
        await withUnsafeContinuation { continuation in
            var _isFinished = false
            lock.lock()
            if isFinished {
                _isFinished = true
            } else {
                continuations.append(continuation)
            }
            lock.unlock()

            if _isFinished {
                continuation.resume()
            }
        }
    }

    func fulfill() {
        var _continuations: [UnsafeContinuation<Void, Never>] = []

        lock.lock()
        #expect(!isFinished, "fulfill called multiple times")
        if !isFinished {
            isFinished = true
            _continuations = continuations
            continuations = []
        }
        lock.unlock()

        for continuation in _continuations {
            continuation.resume()
        }
    }
}
