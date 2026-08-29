// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import Foundation

/// A ``DataLoading`` implementation that downloads the data and then delivers
/// it in small chunks with a delay between them.
///
/// It exists to make the progressive decoding and the download progress
/// visible on a fast connection. It also happens to be a complete example of
/// the ``DataLoading`` contract: call `didReceiveData` for every chunk, call
/// `completion` exactly once, and stop both when the returned token is
/// cancelled.
final class ThrottledDataLoader: DataLoading {
    private let chunkSize: Int
    private let interval: Duration
    private let session: URLSession

    init(chunkSize: Int = 16_384, interval: Duration = .milliseconds(80)) {
        self.chunkSize = chunkSize
        self.interval = interval

        // The demo disables the HTTP cache so that every run downloads
        // the image again.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        let task = Task {
            do {
                let (data, response) = try await session.data(for: request)
                var offset = 0
                while offset < data.count {
                    try await Task.sleep(for: interval)
                    let end = min(offset + chunkSize, data.count)
                    // The pipeline appends the chunks, so send only the new bytes.
                    didReceiveData(data[offset..<end], response)
                    offset = end
                }
                completion(nil)
            } catch {
                // The pipeline doesn't expect any callbacks after cancellation.
                if !Task.isCancelled {
                    completion(error)
                }
            }
        }
        return AnyCancellable { task.cancel() }
    }
}

/// Wraps a closure in a ``Cancellable``.
struct AnyCancellable: Cancellable {
    private let closure: @Sendable () -> Void

    init(_ closure: @escaping @Sendable () -> Void) {
        self.closure = closure
    }

    func cancel() {
        closure()
    }
}
