// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

#if canImport(Combine)
import Combine
#endif

struct BCAnyPublisher<Output, Failure: Error> {
    private let _sink: (@escaping ((BCCompletion<Failure>) -> Void), @escaping ((Output) -> Void)) -> Cancellable

    init(data: Data) where Output == Data {
        self._sink = { onCompletion, onValue in
            onValue(data)
            onCompletion(.finished)
            return NoopCancellable()
        }
    }

    #if canImport(Combine)
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    init<P: Publisher>(_ publisher: P) where P.Output == Output, P.Failure == Failure {
        self._sink = { onCompletion, onValue in
            let cancellable = publisher.sink(receiveCompletion: {
                switch $0 {
                case .finished: onCompletion(.finished)
                case .failure(let error): onCompletion(.failure(error))
                }
            }, receiveValue: {
                onValue($0)
            })
            return BCAnyCancellable(cancellable.cancel)
        }
    }
    #endif

    func sink(receiveCompletion: @escaping ((BCCompletion<Failure>) -> Void), receiveValue: @escaping ((Output) -> Void)) -> Cancellable {
        _sink(receiveCompletion, receiveValue)
    }
}

private final class NoopCancellable: Cancellable {
    func cancel() {
        // Do nothing
    }
}

private final class BCAnyCancellable: Cancellable {
    let closure: () -> Void

    init(_ closure: @escaping () -> Void) {
        self.closure = closure
    }

    func cancel() {
        closure()
    }
}

enum BCCompletion<Failure> where Failure: Error {
    case finished
    case failure(Failure)
}
