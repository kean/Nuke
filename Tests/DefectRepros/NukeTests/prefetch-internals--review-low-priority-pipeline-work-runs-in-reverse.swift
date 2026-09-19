// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

// SUSPECTED BUG: the pipeline starts queued work for requests below `.normal`
// priority in reverse order – the same add-then-lower defect as the
// prefetcher's own queue (see prefetch-internals--low-priority-prefetches-run-
// in-reverse.swift), but in the pipeline's queues, so it affects every
// `.low`/`.veryLow` request, prefetched or not.
//
// Sources/Nuke/Tasks/AsyncTask.swift:97-100
//
//     var operation: TaskQueue.Operation? {
//         didSet {
//             guard priority != .normal else { return }
//             operation?.priority = priority
//         }
//     }
//
// Every call site assigns `operation = queue.add { ... }`
// (TaskFetchOriginalData.swift:83, TaskFetchOriginalImage.swift:138,
// AsyncPipelineTask.swift:56/89, TaskLoadImage.swift:79/133). `TaskQueue.add`
// enqueues at `.normal`, and the `didSet` then lowers the priority. Lowering
// makes `TaskQueue.operationPriorityChanged` *prepend* the operation to the
// lower bucket (TaskQueue.swift:148-149), so each operation that can't start
// right away jumps ahead of the ones queued before it: LIFO instead of the
// FIFO `TaskQueue` documents for work of the same priority. At `.normal` and
// above the order is kept, which is what shows the reversal is an artifact of
// add-then-lower rather than a design choice.
//
// Impact: with more `.low` requests than free data-loading slots (6 by
// default), e.g. a prefetcher with a raised `maxConcurrentRequestCount`, or an
// app that lowers the priority of off-screen cells, the most recently
// requested image is downloaded first and the oldest waits the longest.
//
// Expected: the data loader is called in the order the images were requested:
//           [0, 1, 2, 3]
// Actual (.low / .veryLow): [3, 2, 1, 0]. `.normal` and `.high` pass.
@Suite(.timeLimit(.minutes(5)))
struct LowPriorityPipelineWorkOrderBugRepro {
    @Test(arguments: [ImageRequest.Priority.low, .veryLow, .normal, .high])
    @ImagePipelineActor func dataLoadsStartInTheOrderTheImagesWereRequested(priority: ImageRequest.Priority) async {
        // GIVEN a pipeline that loads one image at a time
        let dataLoader = OrderRecordingDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isRateLimiterEnabled = false
            $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 1)
        }
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        let urls = (0..<4).map { URL(string: "http://test.com/\($0).jpeg")! }

        // WHEN the images are requested one after another
        var tasks: [ImageTask] = []
        _ = await queue.waitForOperations(count: urls.count) {
            for url in urls {
                tasks.append(pipeline.imageTask(with: ImageRequest(url: url, priority: priority)))
            }
        }
        queue.isSuspended = false
        for task in tasks {
            _ = try? await task.response
        }

        // THEN they are downloaded in the same order
        #expect(dataLoader.urls.withLock { $0 } == urls, "priority: \(priority)")
    }
}

private final class OrderRecordingDataLoader: DataLoading, @unchecked Sendable {
    let urls = OSAllocatedUnfairLock<[URL]>(initialState: [])

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let url = request.url!
        urls.withLock { $0.append(url) }
        DispatchQueue.global().async {
            didReceiveData(Test.data, URLResponse(url: url, mimeType: "jpeg", expectedContentLength: Test.data.count, textEncodingName: nil))
            completion(nil)
        }
        return NoCancellable()
    }
}

private struct NoCancellable: Cancellable {
    func cancel() {}
}
