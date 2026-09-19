// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: cancelling a download whose `DataLoading` honors the documented
// cancellation contract leaks a `dataLoadingQueue` slot (and the task, and
// the pipeline it retains) forever. After `maxConcurrentTaskCount` (6 by
// default) such cancellations, the pipeline never loads anything again.
//
// The contract (Documentation/Nuke.docc/Customization/LoadingData/loading-data.md):
// "Cancellation: Return a `Cancellable` whose `cancel()` method stops the
// underlying task and ensures neither `didReceiveData` nor `completion` are
// called after cancellation."
//
// Sources/Nuke/Tasks/TaskFetchOriginalData.swift: `performDataLoad` awaits
// `loadData(with:dataLoader:)`, which suspends in
// `withUnsafeThrowingContinuation` until `finishDataLoad` resumes it – and
// only the loader's `completion` calls `finishDataLoad`. The `onCancelled`
// handler cancels `dataLoadCancellable` but never resumes
// `dataLoadContinuation`, and an unsafe continuation doesn't react to the
// cancellation of its `Task`. So with a loader that stays silent after
// `cancel()`, `performDataLoad` never returns, the `TaskQueue` work never
// finishes, and `TaskQueue.operationFinished()` never frees the slot
// (`Operation.cancel()` only removes *pending* operations).
//
// The default `DataLoader` happens to call `completion(URLError(.cancelled))`
// after `cancel()` (URLSession reports `didCompleteWithError`), which masks
// the leak; `MockDataLoader` with a suspended queue and any custom loader that
// follows the contract don't.
//
// Expected: after the cancelled download, the queue has no operations, and a
//           download of another image completes.
// Actual:   `operationCount == 1` forever; the next download never starts
//           (the test records a timeout).

@Suite(.timeLimit(.minutes(5)))
struct CancelledDownloadLeaksQueueSlotBugTests {
    @Test func cancelledDownloadFreesItsDataLoadingQueueSlot() async throws {
        // GIVEN a pipeline that runs one download at a time, and a loader that
        // follows the cancellation contract
        let loader = _BugContractCompliantLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = loader
            $0.imageCache = nil
            $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 1)
        }
        let stalledURL = try #require(URL(string: "https://example.com/stalled.jpeg"))

        // WHEN a download in flight is cancelled
        let task = pipeline.imageTask(with: stalledURL)
        await loader.started.wait()
        task.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }
        await loader.cancelled.wait()

        // THEN the slot is released...
        await Task { @ImagePipelineActor in }.value
        let operationCount = await pipeline.configuration.dataLoadingQueue.operationCount
        #expect(operationCount == 0)

        // ...and the next image loads
        let finished = TestExpectation()
        let next = pipeline.imageTask(with: Test.url)
        Task {
            _ = try? await next.response
            finished.fulfill()
        }
        await finished.wait(timeout: .seconds(10))
        #expect(next.status.result != nil)
        next.cancel()
    }
}

/// Serves `Test.data` for any URL except the "stalled" one, which never
/// responds; after `cancel()` it never calls back, as the contract requires.
private final class _BugContractCompliantLoader: DataLoading, @unchecked Sendable {
    let started = TestExpectation()
    let cancelled = TestExpectation()

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        guard request.url?.lastPathComponent == "stalled.jpeg" else {
            didReceiveData(Test.data, URLResponse(url: request.url!, mimeType: "image/jpeg", expectedContentLength: Test.data.count, textEncodingName: nil))
            completion(nil)
            return AnonymousCancellable {}
        }
        started.fulfill()
        let cancelled = self.cancelled
        return AnonymousCancellable { cancelled.fulfill() }
    }
}
