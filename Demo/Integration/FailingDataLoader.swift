// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

/// A ``DataLoading`` that fails every request the way a server or a network
/// does, for seeing what an app shows when an image doesn't load without
/// waiting for a server to misbehave.
///
/// It sends nothing anywhere: after a wait that stands for the round trip,
/// it fails the way ``failure`` says, with the error `DataLoader` or
/// `URLSession` would report, so the app handles it as it would the real
/// thing.
///
/// **Cancellation.** As ``BundleDataLoader``: a cancelled load ends with
/// `completion(URLError(.cancelled))`, which frees its data loading slot.
final class FailingDataLoader: DataLoading {
    enum Failure: String, CaseIterable, Identifiable, Sendable {
        /// The server answers `500 Internal Server Error`. `DataLoader` fails
        /// a response whose status is outside 200..<300 before it passes on
        /// any of the body, with ``DataLoader/Error/statusCodeUnacceptable(_:)``,
        /// and so does this.
        case serverError
        /// The server answers `200 OK` and starts on the body, and the
        /// connection drops a third of the way through, with
        /// `URLError(.networkConnectionLost)`.
        case connectionLost

        var id: Self { self }
    }

    let failure: Failure

    init(failure: Failure) {
        self.failure = failure
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        let failure = failure
        let task = Task {
            do {
                try await Task.sleep(for: .milliseconds(400))
                guard let url = request.url else {
                    throw URLError(.badURL)
                }
                switch failure {
                case .serverError:
                    throw DataLoader.Error.statusCodeUnacceptable(500)
                case .connectionLost:
                    // 32 KB of the 96 KB the response promises. The pipeline
                    // reads an unfinished body only to decode previews, which
                    // is off by default, so the bytes can be zeros.
                    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "98304"])!
                    for _ in 0..<4 {
                        try await Task.sleep(for: .milliseconds(200))
                        didReceiveData(Data(count: 8_192), response)
                    }
                    // With the description and the URL `URLSession` gives the
                    // error, which is what an app prints.
                    throw URLError(.networkConnectionLost, userInfo: [
                        NSLocalizedDescriptionKey: "The network connection was lost.",
                        NSURLErrorFailingURLErrorKey: url
                    ])
                }
            } catch {
                completion(Task.isCancelled ? URLError(.cancelled) : error)
            }
        }
        return AnyCancellable { task.cancel() }
    }
}
