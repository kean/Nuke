// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

// BUG: a custom `DataLoading` that follows the documented cancellation
// contract permanently occupies a `dataLoadingQueue` slot for every download
// cancelled in flight; once all slots (6 by default) are taken, the pipeline
// never loads anything from the network again.
//
// Documentation/Nuke.docc/Customization/LoadingData/loading-data.md, "The
// DataLoading Protocol Contract":
//   **Cancellation:** Return a `Cancellable` whose `cancel()` method stops the
//   underlying task and ensures neither `didReceiveData` nor `completion` are
//   called after cancellation.
//
// Sources/Nuke/Tasks/TaskFetchOriginalData.swift `loadData(with:dataLoader:)`
// suspends in `withUnsafeThrowingContinuation`, which only `completion`
// resumes. Cancelling the image task cancels the `TaskQueue` operation's
// Swift `Task` and calls `dataLoadCancellable?.cancel()`, but neither resumes
// the continuation, so `performDataLoad` never returns and the queue never
// decrements `runningCount` (TaskQueue.execute waits for `work()` to return).
// The task, its `TaskFetchOriginalData` and the continuation leak too.
//
// It works with `DataLoader` only because `URLSession` does call the
// completion (with `URLError.cancelled`) after `cancel()` — contradicting the
// documented contract (the `DataLoading.completion` doc comment also says it
// "must be called once", which is the rule the pipeline actually needs).
//
// Expected: after the first download is cancelled, the second one (on a queue
//           with a single slot) completes.
// Actual:   the second download never starts; the wait times out.

@Suite(.timeLimit(.minutes(2)))
struct DataLoadingCancelContractDeadlockBugTests {
    @Test func cancelledDownloadReleasesDataLoadingQueueSlot() async throws {
        // GIVEN a data loader that follows the documented contract and a
        // pipeline that runs one download at a time
        let loader = _ContractFollowingDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = loader
            $0.imageCache = nil
            $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 1)
        }

        // GIVEN a download in flight
        let first = pipeline.imageTask(with: URL(string: "https://example.com/stalled.jpeg")!)
        let firstResult = Task { try? await first.response }
        await loader.stalledRequestStarted.wait()

        // WHEN it's cancelled
        first.cancel()
        _ = await firstResult.value

        // THEN the next download can use the slot
        let finished = TestExpectation()
        let second = pipeline.imageTask(with: URL(string: "https://example.com/fast.jpeg")!)
        let secondResult = Task {
            let response = try? await second.response
            finished.fulfill()
            return response
        }
        await finished.wait(timeout: .seconds(10))
        second.cancel()
        let response = await secondResult.value
        #expect(response != nil)
    }
}

private final class _ContractFollowingDataLoader: DataLoading, @unchecked Sendable {
    let stalledRequestStarted = TestExpectation()

    func loadData(with request: URLRequest,
                  didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
                  completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let isCancelled = OSAllocatedUnfairLock(initialState: false)
        if request.url?.lastPathComponent == "stalled.jpeg" {
            // Waits for the server forever; `cancel()` stops the work and,
            // as documented, calls neither closure afterwards.
            stalledRequestStarted.fulfill()
        } else {
            DispatchQueue.global().async {
                guard !isCancelled.withLock({ $0 }) else { return }
                let response = URLResponse(url: request.url!, mimeType: "image/jpeg", expectedContentLength: Test.data.count, textEncodingName: nil)
                didReceiveData(Test.data, response)
                completion(nil)
            }
        }
        return _Cancellable { isCancelled.withLock { $0 = true } }
    }
}

private struct _Cancellable: Cancellable {
    let onCancel: @Sendable () -> Void
    func cancel() { onCancel() }
}
