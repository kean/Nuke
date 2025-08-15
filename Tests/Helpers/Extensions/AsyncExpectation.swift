import Foundation
import Combine
import Testing

final class AsyncExpectation<Value: Sendable>: @unchecked Sendable {
    private var state = Mutex(wrappedValue: State())

    var cancellables: [AnyCancellable] = []

    private struct State {
        var value: Value?
        var continuation: UnsafeContinuation<Value, Never>?
        var isInvalidated = false
        var count = 1
    }

    var value: Value {
        get async {
            await wait()
        }
    }

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

    func invalidate() {
        state.withLock {
            $0.isInvalidated = true
        }
    }

    func fulfill(with value: Value) {
        let continuation: UnsafeContinuation<Value, Never>? = state.withLock {
            guard !$0.isInvalidated else {
                return nil
            }
            $0.count -= 1
            guard $0.count == 0 else {
                return nil
            }
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
    convenience init(expectedFulfillmentCount: Int) {
        self.init()
        self.state.withLock {
            $0.count = expectedFulfillmentCount
        }
    }

    func fulfill() {
        fulfill(with: ())
    }
}
