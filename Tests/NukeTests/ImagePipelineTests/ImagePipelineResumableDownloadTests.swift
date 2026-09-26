// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// Resumable downloads end-to-end: what the pipeline sends back to the server
/// on the next attempt, and what it does with the answer.
///
/// - seealso: ``ImagePipeline/Configuration-swift.struct/isResumableDataEnabled``
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineResumableDownloadTests {
    private let server: MockRangeServer
    private let dataCache: MockDataCache
    private let pipeline: ImagePipeline

    init() {
        let server = MockRangeServer(data: Test.data, validator: ["ETag": "\"v1\""])
        let dataCache = MockDataCache()
        self.server = server
        self.dataCache = dataCache
        self.pipeline = ImagePipeline {
            $0.dataLoader = server
            $0.dataCache = dataCache
            $0.imageCache = nil
        }
    }

    // MARK: - Failure

    @Test func failedDownloadIsResumedWithTheETag() async throws {
        // GIVEN a download that failed after 10000 bytes
        server.steps = [.fail(after: 10000), .serve]
        await #expect(throws: ImagePipeline.Error.self) {
            try await pipeline.data(for: Test.request)
        }

        // WHEN
        let (data, response) = try await pipeline.data(for: Test.request)

        // THEN the server is asked for the rest of the bytes
        let request = try #require(server.requests.last)
        #expect(request.value(forHTTPHeaderField: "Range") == "bytes=10000-")
        #expect(request.value(forHTTPHeaderField: "If-Range") == "\"v1\"")

        // THEN the resumed bytes are stitched together with the rest
        #expect((response as? HTTPURLResponse)?.statusCode == 206)
        #expect(data == Test.data)
        #expect(dataCache.store[Test.url.absoluteString] == Test.data)
    }

    /// When the attempt that was supposed to resume the download fails before
    /// the server responds, the pipeline has already taken the bytes out of the
    /// storage – it has to put them back for the attempt after it.
    @Test func failureBeforeTheServerRespondsKeepsTheBytes() async throws {
        // GIVEN a download that failed after 10000 bytes, and a retry that
        // failed without a response
        server.steps = [.fail(after: 10000), .failBeforeResponse, .serve]
        _ = try? await pipeline.data(for: Test.request)
        await #expect(throws: ImagePipeline.Error.self) {
            try await pipeline.data(for: Test.request)
        }

        // WHEN
        let (data, _) = try await pipeline.data(for: Test.request)

        // THEN the third attempt still resumes where the first one left off
        #expect(server.requests.count == 3)
        #expect(server.requests.map { $0.value(forHTTPHeaderField: "Range") } == [nil, "bytes=10000-", "bytes=10000-"])
        #expect(data == Test.data)
    }

    /// The same goes for an attempt that `willLoadData` rejects: the bytes
    /// are taken out of the storage before the delegate is asked.
    @Test func delegateFailureKeepsTheBytes() async throws {
        // GIVEN a download that failed after 10000 bytes, and a retry that
        // the delegate rejected
        let attempts = EventCounter()
        let delegate = MockWillLoadDataDelegate { request in
            attempts.increment()
            if attempts.count == 2 {
                throw URLError(.userAuthenticationRequired)
            }
            return request
        }
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = server
            $0.imageCache = nil
        }
        server.steps = [.fail(after: 10000), .serve]
        _ = try? await pipeline.data(for: Test.request)
        await #expect(throws: ImagePipeline.Error.self) {
            try await pipeline.data(for: Test.request)
        }

        // WHEN
        let (data, _) = try await pipeline.data(for: Test.request)

        // THEN
        #expect(server.requests.count == 2)
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=10000-")
        #expect(data == Test.data)
    }

    @Test func resumedDownloadThatFailsAgainKeepsResumableData() async throws {
        // GIVEN a server that fails the first attempt at 8000 bytes and the
        // resumed one at 20000 bytes – more than the 206 "Content-Length"
        server.steps = [.fail(after: 8000), .fail(after: 20000), .serve]

        // WHEN the download fails, is resumed, and fails again
        _ = try? await pipeline.data(for: Test.request)
        _ = try? await pipeline.data(for: Test.request)
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=8000-")

        // THEN the third attempt resumes from where the second one failed
        let (data, _) = try await pipeline.data(for: Test.request)
        #expect(data == Test.data)
        #expect(server.requests.count == 3)
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=20000-")
    }

    @Test func completedDownloadLeavesNoResumableData() async throws {
        // GIVEN an initial partial download that fails and stores resumable data
        server.steps = [.fail(after: 10000), .serve]
        _ = try? await pipeline.imageTask(with: Test.request).response

        // WHEN the download is resumed and completes successfully (all bytes delivered)
        _ = try await pipeline.imageTask(with: Test.request).response

        // THEN no resumable data remains in storage: the completed download doesn't
        // produce a partial entry (ResumableData init requires data.count < Content-Length).
        let stored = await ResumableDataStorage.shared.removeResumableData(
            for: ImageRequest(url: Test.url),
            pipeline: pipeline
        )
        #expect(stored == nil)
    }

    // MARK: - Cancellation

    /// The docs promise to resume after "either a failure or a cancellation".
    @Test func cancelledDownloadIsResumed() async throws {
        // GIVEN a download that stalls after 8000 bytes
        server.steps = [.stall(after: 8000), .serve]
        let task = pipeline.imageTask(with: Test.request)
        for await progress in task.progress {
            #expect(progress == ImageTask.Progress(completed: 8000, total: 22789))
            break
        }

        // WHEN it gets cancelled
        task.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }
        #expect(server.cancelCount == 1)

        // THEN the next attempt picks up from where it was cancelled
        let (data, response) = try await pipeline.data(for: Test.request)
        let request = try #require(server.requests.last)
        #expect(request.value(forHTTPHeaderField: "Range") == "bytes=8000-")
        #expect((response as? HTTPURLResponse)?.statusCode == 206)
        #expect(data == Test.data)
    }

    @Test func resumableDataIsKeptWhenCancelledBeforeServerResponds() async throws {
        // GIVEN a pipeline whose delegate suspends the second attempt right
        // before data loading
        let attempts = EventCounter()
        let entered = AsyncGate(), proceed = AsyncGate()
        let delegate = MockWillLoadDataDelegate { request in
            attempts.increment()
            if attempts.count == 2 {
                entered.open()
                await proceed.wait()
            }
            return request
        }
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = server
            $0.imageCache = nil
        }

        // GIVEN an initial partial download that stores resumable data
        server.steps = [.fail(after: 10000), .serve]
        _ = try? await pipeline.imageTask(with: Test.request).response

        // WHEN the next attempt is cancelled while `willLoadData` is suspended,
        // after the pipeline has already taken the data out of the storage
        let task = pipeline.imageTask(with: Test.request)
        let response = Task { try await task.response }
        await entered.wait()
        task.cancel()
        await drainPipeline()
        proceed.open()
        _ = try? await response.value
        await drainPipeline()

        // THEN the resumable data is still there for the next attempt
        let stored = await ResumableDataStorage.shared.removeResumableData(
            for: ImageRequest(url: Test.url),
            pipeline: pipeline
        )
        #expect(stored != nil)
    }

    // MARK: - Progress

    @Test func thatProgressIsReported() async throws {
        // Given an initial request failed mid download
        server.chunkSize = 3799
        server.steps = [.fail(after: 11397), .serve]

        // Expect the progress for the first part of the download to be reported.
        var initialProgress: [ImageTask.Progress] = []
        do {
            let task = pipeline.imageTask(with: Test.request)
            for await progress in task.progress {
                initialProgress.append(progress)
            }
            _ = try await task.response
        } catch {
            // Expected failure
        }

        #expect(initialProgress == [
            ImageTask.Progress(completed: 3799, total: 22789),
            ImageTask.Progress(completed: 7598, total: 22789),
            ImageTask.Progress(completed: 11397, total: 22789)
        ])

        // Expect progress closure to continue reporting the progress of the
        // entire download
        var remainingProgress: [ImageTask.Progress] = []
        let task2 = pipeline.imageTask(with: Test.request)
        for await progress in task2.progress {
            remainingProgress.append(progress)
        }
        _ = try await task2.response

        #expect(remainingProgress == [
            ImageTask.Progress(completed: 15196, total: 22789),
            ImageTask.Progress(completed: 18995, total: 22789),
            ImageTask.Progress(completed: 22789, total: 22789)
        ])
    }

    @Test func resumedBytesAreReportedInTheMetrics() async throws {
        // GIVEN a pipeline that records diagnostics and a download that failed
        // mid-way
        server.steps = [.fail(after: 11397), .serve]
        let pipeline = ImagePipeline {
            $0.dataLoader = server
            $0.imageCache = nil
            $0.isDiagnosticsEnabled = true
        }
        let task1 = pipeline.imageTask(with: Test.request)
        _ = try? await task1.response
        let metrics1 = try #require(task1.metrics)
        #expect(metrics1.outcome == .failure)
        #expect(metrics1.bytes?.downloaded == 11397)
        #expect(metrics1.bytes?.expected == 22789)
        let failed = try #require(metrics1.jobs.last?.stages.first { $0.kind == .download })
        #expect(failed.resumedBytes == 0)

        // WHEN the download is resumed
        let task2 = pipeline.imageTask(with: Test.request)
        _ = try await task2.response

        // THEN the resumed bytes are reported
        let metrics2 = try #require(task2.metrics)
        #expect(metrics2.bytes?.downloaded == 22789)
        #expect(metrics2.bytes?.resumed == 11397)
        #expect(metrics2.bytes?.expected == 22789)
        let resumed = try #require(metrics2.jobs.last?.stages.first { $0.kind == .download })
        #expect(resumed.statusCode == 206)
    }

    /// On a "206 Partial Content" response, `expectedContentLength` covers only
    /// the remaining bytes while the accumulated data already contains the
    /// resumed prefix. The guard that decides whether to give the decoder a
    /// chance to produce a preview used to compare the two directly, so it was
    /// never satisfied and the resumed download produced no previews at all.
    @Test func previewsAreDeliveredWhenTheDownloadIsResumed() async throws {
        // GIVEN a pipeline with progressive decoding enabled, and a progressive
        // JPEG served in three chunks, one scan each
        let data = Test.data(name: "progressive", extension: "jpeg")
        server.resource = (data, ["ETag": "\"v1\""])
        server.chunkSize = data.count / 3
        let pipeline = ImagePipeline {
            $0.dataLoader = server
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
        }

        // GIVEN an initial download that delivers one scan and then fails
        server.steps = [.fail(after: data.count / 3), .serve]
        var initialPreviews: [ImageResponse] = []
        let initialTask = pipeline.imageTask(with: Test.request)
        for await preview in initialTask.previews {
            initialPreviews.append(preview)
        }
        await #expect(throws: ImagePipeline.Error.self) {
            try await initialTask.response
        }
        #expect(initialPreviews.count == 1)

        // WHEN the download is resumed with "206 Partial Content"
        var previews: [ImageResponse] = []
        let task = pipeline.imageTask(with: Test.request)
        for await preview in task.previews {
            previews.append(preview)
        }
        let response = try await task.response

        // THEN the remaining scans are still delivered as previews
        #expect((response.urlResponse as? HTTPURLResponse)?.statusCode == 206)
        #expect(previews.count == 1)
        #expect(previews.allSatisfy { $0.container.isPreview })

        // THEN the final image is produced
        #expect(!response.container.isPreview)
    }

    // MARK: - Server Responses

    /// A server is free to ignore "Range" (or reject "If-Range") and send the
    /// whole resource with "200 OK" – the resumed bytes must not end up in
    /// front of it.
    @Test func serverIgnoringTheRangeRestartsTheDownload() async throws {
        // GIVEN
        server.steps = [.fail(after: 10000), .ignoreRange]
        _ = try? await pipeline.data(for: Test.request)

        // WHEN
        let progress = LockedArray<ImageTask.Progress>()
        let task = pipeline.makeStartedImageTask(with: Test.request, isDataTask: true) { event, _ in
            if case .progress(let value) = event { progress.append(value) }
        }
        let response = try await task.response

        // THEN the data is the resource, not the resumed bytes followed by it
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=10000-")
        #expect(response.urlResponse.map { ($0 as? HTTPURLResponse)?.statusCode } == 200)
        #expect(response.container.data == Test.data)
        #expect(progress.values.last == ImageTask.Progress(completed: 22789, total: 22789))
        #expect(progress.values.allSatisfy { $0.total == 22789 })
    }

    /// Foundation reports a "Content-Length" it can't represent as
    /// `Int64.max`, so adding the resumed bytes to it must not overflow.
    @Test func resumedResponseWithHugeContentLengthExceedsMaximumSize() async throws {
        // GIVEN a download that failed after 10000 bytes
        server.steps = [.fail(after: 10000), .serveAdvertising(contentLength: "99999999999999999999")]
        _ = try? await pipeline.data(for: Test.request)

        // WHEN the resumed response advertises a length above the limit
        await #expect(throws: ImagePipeline.Error.dataDownloadExceededMaximumSize) {
            try await pipeline.data(for: Test.request)
        }

        // THEN
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=10000-")
    }

    @Test func resumedResponseWithHugeContentLengthLoadsWithoutSizeLimit() async throws {
        // GIVEN a pipeline without a size limit
        let pipeline = ImagePipeline {
            $0.dataLoader = server
            $0.imageCache = nil
            $0.maximumResponseDataSize = nil
        }
        server.steps = [.fail(after: 10000), .serveAdvertising(contentLength: "99999999999999999999")]
        _ = try? await pipeline.data(for: Test.request)

        // WHEN
        let (data, response) = try await pipeline.data(for: Test.request)

        // THEN
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=10000-")
        #expect((response as? HTTPURLResponse)?.statusCode == 206)
        #expect(data == Test.data)
    }

    @Test func responseWithHugeContentLengthLoadsWithoutSizeLimit() async throws {
        // GIVEN a pipeline without a size limit
        let pipeline = ImagePipeline {
            $0.dataLoader = server
            $0.imageCache = nil
            $0.maximumResponseDataSize = nil
        }
        server.steps = [.serveAdvertising(contentLength: "99999999999999999999")]

        // WHEN
        let (data, response) = try await pipeline.data(for: Test.request)

        // THEN
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(data == Test.data)
    }

    /// "If-Range" is what keeps the bytes of the old version out of the new
    /// one: a server with a different version answers with all of it.
    @Test func resourceThatChangedIsDownloadedFromScratch() async throws {
        // GIVEN a download that failed after 10000 bytes
        server.steps = [.fail(after: 10000), .serve, .fail(after: 5000), .serve]
        _ = try? await pipeline.data(for: Test.request)

        // WHEN the resource changes before the next attempt
        let newData = Test.data(name: "fixture-tiny", extension: "jpeg")
        server.resource = (newData, ["ETag": "\"v2\""])
        let (data, response) = try await pipeline.data(for: Test.request)

        // THEN
        #expect(server.requests.last?.value(forHTTPHeaderField: "If-Range") == "\"v1\"")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(data == newData)

        // THEN the next interruption resumes with the new validator
        _ = try? await pipeline.data(for: ImageRequest(url: Test.url, options: [.disableDiskCacheReads]))
        let (resumed, _) = try await pipeline.data(for: ImageRequest(url: Test.url, options: [.disableDiskCacheReads]))
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=5000-")
        #expect(server.requests.last?.value(forHTTPHeaderField: "If-Range") == "\"v2\"")
        #expect(resumed == newData)
    }

    // MARK: - Configuration

    @Test func resumableDataIsNotUsedWhenDisabled() async throws {
        // GIVEN
        let pipeline = ImagePipeline {
            $0.dataLoader = server
            $0.imageCache = nil
            $0.isResumableDataEnabled = false
        }
        server.steps = [.fail(after: 10000), .serve]
        _ = try? await pipeline.data(for: Test.request)

        // WHEN
        let (data, response) = try await pipeline.data(for: Test.request)

        // THEN
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == nil)
        #expect(server.requests.last?.value(forHTTPHeaderField: "If-Range") == nil)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(data == Test.data)
    }

    @Test func resumableDataBelongsToThePipelineThatDownloadedIt() async throws {
        // GIVEN a download that failed in one pipeline
        let otherPipeline = ImagePipeline {
            $0.dataLoader = server
            $0.imageCache = nil
        }
        server.steps = [.fail(after: 10000), .serve, .serve]
        _ = try? await pipeline.data(for: Test.request)

        // WHEN the other pipeline loads the same image
        _ = try await otherPipeline.data(for: Test.request)

        // THEN it starts from scratch and leaves the bytes where they are
        #expect(server.requests.count == 2)
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == nil)
        _ = try await pipeline.data(for: Test.request)
        #expect(server.requests.count == 3)
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=10000-")
    }

    // MARK: - Delegate

    /// The docs say that `willLoadData` is called "after resumable data headers
    /// are applied".
    @Test func willLoadDataSeesTheResumeHeaders() async throws {
        // GIVEN
        let delegate = MockWillLoadDataDelegate()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = server
            $0.imageCache = nil
        }
        server.steps = [.fail(after: 10000), .serve]
        _ = try? await pipeline.data(for: Test.request)

        // WHEN
        _ = try await pipeline.data(for: Test.request)

        // THEN
        let requests = delegate.requests
        #expect(requests.count == 2)
        #expect(requests.first?.value(forHTTPHeaderField: "Range") == nil)
        #expect(requests.last?.value(forHTTPHeaderField: "Range") == "bytes=10000-")
        #expect(requests.last?.value(forHTTPHeaderField: "If-Range") == "\"v1\"")
    }
}
