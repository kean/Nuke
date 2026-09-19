// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG (inconsistency): an empty local resource – a zero-length file or an
// empty `data:` URL – "succeeds" with empty data, while the same empty payload
// from the data loader or from a custom `data` closure fails with
// `ImagePipeline.Error.dataIsEmpty`.
//
// Sources/Nuke/Tasks/TaskFetchOriginalData.swift: the network path
// (`dataTaskDidFinish`, "Sanity check") and the closure path
// (`asyncDataDidFinish`) both reject empty data with `.dataIsEmpty`. The
// local-resource branch in `start()` sends whatever `Data(contentsOf:)`
// returned with `send(value: (data, nil), isCompleted: true)` and skips the
// check, so `data(for:)` returns `(Data(), nil)`, and `image(for:)` fails in
// the decoder with an error that doesn't say the data was empty.
//
// Expected: `.dataIsEmpty`, the same as for an empty download.
// Actual:   `data(for:)` returns zero bytes.

@Suite(.timeLimit(.minutes(5)))
struct EmptyLocalResourceSucceedsBugTests {
    @Test func emptyFileFailsWithDataIsEmpty() async throws {
        // GIVEN
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nuke-empty-\(UUID().uuidString).jpeg")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // WHEN/THEN
        await #expect(throws: ImagePipeline.Error.dataIsEmpty) {
            try await pipeline.data(for: ImageRequest(url: url))
        }
    }

    @Test func emptyDataURLFailsWithDataIsEmpty() async throws {
        // GIVEN
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }
        let url = try #require(URL(string: "data:image/jpeg;base64,"))

        // WHEN/THEN
        await #expect(throws: ImagePipeline.Error.dataIsEmpty) {
            try await pipeline.data(for: ImageRequest(url: url))
        }
    }

    /// The control: the same empty payload from the data loader.
    @Test func emptyDownloadFailsWithDataIsEmpty() async throws {
        let dataLoader = MockDataLoader()
        dataLoader.results[Test.url] = .success((Data(), Test.urlResponse))
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        await #expect(throws: ImagePipeline.Error.dataIsEmpty) {
            try await pipeline.data(for: Test.request)
        }
    }
}
