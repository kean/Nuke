// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation
@preconcurrency import Combine

final class DataPublisher {
    let id: String
    private let _sink: (@escaping ((PublisherCompletion) -> Void), @escaping ((Data) -> Void)) -> any Cancellable

    init<P: Publisher>(id: String, _ publisher: P) where P.Output == Data {
        self.id = id
        self._sink = { onCompletion, onValue in
            let cancellable = publisher.sink(receiveCompletion: {
                switch $0 {
                case .finished: onCompletion(.finished)
                case .failure(let error): onCompletion(.failure(error))
                }
            }, receiveValue: {
                onValue($0)
            })
            return AnonymousCancellable { cancellable.cancel() }
        }
    }

    convenience init(id: String, _ data: @Sendable @escaping () async throws -> Data) {
        self.init(id: id, publisher(from: data))
    }

    func sink(receiveCompletion: @escaping ((PublisherCompletion) -> Void), receiveValue: @escaping ((Data) -> Void)) -> any Cancellable {
        _sink(receiveCompletion, receiveValue)
    }
}

private func publisher(from closure: @Sendable @escaping () async throws -> Data) -> AnyPublisher<Data, Error> {
    let subject = PassthroughSubject<Data, Error>()
    Task {
        do {
            let data = try await closure()
            subject.send(data)
            subject.send(completion: .finished)
        } catch {
            subject.send(completion: .failure(error))
        }
    }
    return subject.eraseToAnyPublisher()
}

enum PublisherCompletion {
    case finished
    case failure(Error)
}
