import Foundation
import Combine
import Testing

@testable import Nuke

final class AsyncExpectation<Value: Sendable>: @unchecked Sendable {
    private var state = Mutex(wrappedValue: State())
    private var cancellables: [AnyCancellable] = []

    private struct State {
        var value: Value?
        var continuation: UnsafeContinuation<Value, Never>?
    }

    init() {}

    @discardableResult
    func wait() async -> Value {
        await withUnsafeContinuation { continuation in
            let value = state.withLock {
                if $0.value == nil {
                    $0.continuation = continuation
                }
                return $0.value
            }
            if let value {
                continuation.resume(returning: value)
            }
        }
    }

    func fulfill(with value: Value) {
        let continuation = state.withLock {
            #expect($0.value == nil, "fulfill called multiple times")
            $0.value = value
            let continuation = $0.continuation
            $0.continuation = nil
            return continuation
        }
        continuation?.resume(returning: value)
    }
}

extension AsyncExpectation where Value == Void {
    func fulfill() {
        fulfill(with: ())
    }

    convenience init(notification: Notification.Name, object: AnyObject) {
        self.init()

        NotificationCenter.default
            .publisher(for: notification, object: object)
            .sink { [weak self] _ in self?.fulfill() }
            .store(in: &cancellables)
    }
}
