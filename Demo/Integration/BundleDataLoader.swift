// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

/// A ``DataLoading`` that answers requests from files in the app bundle
/// rather than from the network: what an app writes for the images it ships
/// with, or for previews and UI tests that run without a server.
///
/// It knows a file for each URL in ``files``. ``canLoad(_:)`` says whether it
/// knows one for a request, so a pipeline's delegate can send it those
/// requests and leave the rest to the configured loader, the way the Custom
/// Data Loader screen installs it.
///
/// It reads the file and hands it to the pipeline in chunks, a pause apart,
/// so that the chunks can be watched arriving and a load can be cancelled
/// halfway. An app would hand the file on in one chunk, at once.
///
/// **Cancellation.** A cancelled load ends with a call to `completion`, with
/// `URLError(.cancelled)`, the way a `DataLoader` load does. The documentation
/// of ``DataLoading`` asks for no call at all, which is what
/// ``ThrottledDataLoader`` does, but the pipeline frees a load's data loading
/// slot only when `completion` is called. By then the pipeline has let go of
/// the task, so the call reaches nothing of the app's.
final class BundleDataLoader: DataLoading {
    /// The name of the file in the bundle that answers each URL.
    let files: [URL: String]
    let chunkSize: Int
    let interval: Duration

    init(files: [URL: String], chunkSize: Int = 4_096, interval: Duration = .milliseconds(200)) {
        self.files = files
        self.chunkSize = chunkSize
        self.interval = interval
    }

    /// Whether the bundle has a file for the request.
    func canLoad(_ request: ImageRequest) -> Bool {
        request.url.map { files[$0] != nil } ?? false
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        let task = Task {
            do {
                guard let url = request.url, let name = files[url],
                      let file = Bundle.main.url(forResource: name, withExtension: nil) else {
                    throw URLError(.fileDoesNotExist)
                }
                let data = try Data(contentsOf: file)
                // Not an `HTTPURLResponse`: no status code to check, and no
                // validators, so the pipeline doesn't keep a cancelled load
                // to resume.
                let response = URLResponse(url: url, mimeType: nil, expectedContentLength: data.count, textEncodingName: nil)
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
                // After a cancel too: the call frees the load's slot.
                completion(Task.isCancelled ? URLError(.cancelled) : error)
            }
        }
        return AnyCancellable { task.cancel() }
    }
}
