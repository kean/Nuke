import Foundation
import Combine
import Testing

final class AsyncExpectation: @unchecked Sendable {
    private var state = Mutex(wrappedValue: State())
    private var cancellables: [AnyCancellable] = []

    private struct State {
        var isFinished = false
        var continuation: UnsafeContinuation<Void, Never>?
    }

    init(notification: Notification.Name, object: AnyObject) {
        NotificationCenter.default
            .publisher(for: notification, object: object)
            .sink { [weak self] _ in self?.fulfill() }
            .store(in: &cancellables)
    }

    func wait() async {
        await withUnsafeContinuation { continuation in
            let isFinished = state.withLock {
                if !$0.isFinished {
                    $0.continuation = continuation
                }
                return $0.isFinished
            }
            if isFinished {
                continuation.resume()
            }
        }
    }

    func fulfill() {
        let continuation = state.withLock {
            #expect(!$0.isFinished, "fulfill called multiple times")
            $0.isFinished = true
            let continuation = $0.continuation
            $0.continuation = nil
            return continuation
        }
        continuation?.resume()
    }
}
