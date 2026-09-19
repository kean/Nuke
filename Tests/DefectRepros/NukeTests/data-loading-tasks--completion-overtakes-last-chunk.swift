// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: the pipeline can drop data chunks when a `DataLoading` calls
// `completion` from a thread with a higher QoS than the thread that delivered
// the chunks, and reports the truncated data as a success.
//
// The `DataLoading` contract (Documentation/Nuke.docc/Customization/LoadingData/
// loading-data.md) says: "`didReceiveData` and `completion` can be called on
// any thread", and "Do not call `didReceiveData` after calling `completion`".
// The loader below honors both: each call returns before the next one starts.
//
// Sources/Nuke/Tasks/TaskFetchOriginalData.swift `loadData(with:dataLoader:)`
// hops every callback to the pipeline actor in a separate unstructured task:
//
//     Task { @ImagePipelineActor in self?.dataTaskDidReceive(chunk: chunk, response: response) }
//     ...
//     Task { @ImagePipelineActor in self?.finishDataLoad(error: error) }
//
// Each task inherits the priority of the calling thread, and the actor runs
// its pending jobs highest priority first. When the completion's task outranks
// the chunks' tasks, `finishDataLoad` runs first, clears
// `dataLoadContinuation`, and `dataTaskDidReceive` then drops every chunk
// (`guard dataLoadContinuation != nil`). Depending on how many chunks got in
// first, the request fails with `.dataIsEmpty` or "succeeds" with truncated
// data – which also gets written to the disk cache.
//
// Expected: `data(for:)` returns all 22789 bytes.
// Actual:   the request fails with `.dataIsEmpty` (the chunks never make it).

@Suite(.timeLimit(.minutes(5)))
struct CompletionOvertakesLastChunkBugTests {
    @Test func chunksDeliveredBeforeTheCompletionAreNotDropped() async throws {
        // GIVEN a loader that delivers the chunks from a background thread and
        // completes from a user-interactive one
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = _SplitThreadDataLoader()
            $0.dataCache = dataCache
            $0.imageCache = nil
        }

        // WHEN
        let (data, _) = try await pipeline.data(for: Test.request)

        // THEN
        #expect(data == Test.data)
        #expect(dataCache.store[Test.url.absoluteString] == Test.data)
    }
}

private final class _SplitThreadDataLoader: DataLoading, @unchecked Sendable {
    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let data = Test.data
        let response = URLResponse(url: request.url!, mimeType: "image/jpeg", expectedContentLength: data.count, textEncodingName: nil)
        let half = data.count / 2
        // Each call finishes before the next one starts.
        _run(qos: .background) { didReceiveData(data[0..<half], response) }
        _run(qos: .background) { didReceiveData(data[half...], response) }
        _run(qos: .userInteractive) { completion(nil) }
        return AnonymousCancellable {}
    }
}

/// Runs the work on a new thread with the given QoS and waits for it.
private func _run(qos: QualityOfService, _ work: @escaping @Sendable () -> Void) {
    let done = DispatchSemaphore(value: 0)
    let thread = Thread {
        work()
        done.signal()
    }
    thread.qualityOfService = qos
    thread.start()
    done.wait()
}
