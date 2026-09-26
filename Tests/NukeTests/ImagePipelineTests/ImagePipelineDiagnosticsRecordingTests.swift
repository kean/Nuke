// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// What the pipeline records for a task in the situations the happy path
/// doesn't reach: the runtime switch flipped mid-task, a task that never
/// started, every way a task fails, and the work that never left its queue.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDiagnosticsRecordingTests {
    private let dataLoader: MockDataLoader
    private let imageCache: MockImageCache
    private let dataCache: MockDataCache
    private let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        let imageCache = MockImageCache()
        let dataCache = MockDataCache()
        self.dataLoader = dataLoader
        self.imageCache = imageCache
        self.dataCache = dataCache
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
            $0.isDiagnosticsEnabled = true
        }
    }

    // MARK: - When the Record Is Available

    @Test func metricsAreNilUntilTheTaskFinishes() async throws {
        // GIVEN a task held in its download
        dataLoader.isSuspended = true
        let started = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.imageTask(with: Test.request)
        await started.wait()

        // THEN there is no record while it runs
        #expect(task.metrics == nil)
        #expect(task.status.metrics == nil)

        // WHEN
        dataLoader.isSuspended = false
        _ = try await task.response

        // THEN
        #expect(task.metrics != nil)
        #expect(task.status.metrics?.taskID == task.taskId)
    }

    /// The record is written before the terminal event is sent, so an
    /// observer of the event stream can read it off the task.
    @Test func finishedEventObserversSeeTheRecord() async throws {
        // GIVEN
        dataLoader.isSuspended = true
        let started = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.imageTask(with: Test.request)
        await started.wait()

        // WHEN an observer subscribes while the task runs, so it receives the
        // terminal event as it is sent rather than the replay a late
        // subscriber gets
        let stream = task.events
        let events = Task {
            var recordAtFinish: ImageTask.Metrics?
            var didFinish = false
            for await event in stream {
                if case .finished = event {
                    didFinish = true
                    recordAtFinish = task.metrics
                }
            }
            return (didFinish, recordAtFinish)
        }
        dataLoader.isSuspended = false
        let (finished, record) = await events.value

        // THEN
        #expect(finished)
        let metrics = try #require(record)
        #expect(metrics.outcome == .success)
        #expect(metrics.taskID == task.taskId)
    }

    // MARK: - Runtime Switch

    /// "The switch is read once per task, when the pipeline starts it, so a
    /// task is either recorded in full or not at all."
    @Test func turningTheSwitchOffMidTaskKeepsTheRecord() async throws {
        // GIVEN a task the pipeline started with the switch on
        dataLoader.isSuspended = true
        let started = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.imageTask(with: Test.request)
        await started.wait()

        // WHEN the switch is turned off while it runs
        pipeline.diagnostics.isEnabled = false
        dataLoader.isSuspended = false
        _ = try await task.response

        // THEN it is recorded in full
        let metrics = try #require(task.metrics)
        #expect(metrics.outcome == .success)
        #expect(metrics.jobs.map(\.kind) == [.loadImage, .fetchOriginalImage, .fetchOriginalData])
        #expect(metrics.jobs.allSatisfy { $0.outcome == .success })
        let download = try #require(metrics.jobs.last?.stages.first { $0.kind == .download })
        #expect(download.bytes == 22789)

        // THEN the next task is not
        let next = pipeline.imageTask(with: ImageRequest(url: URL(string: "https://example.com/next.jpeg")!))
        _ = try await next.response
        #expect(next.metrics == nil)
    }

    @Test func turningTheSwitchOnMidTaskDoesNotRecordIt() async throws {
        // GIVEN a task the pipeline started with the switch off
        pipeline.diagnostics.isEnabled = false
        dataLoader.isSuspended = true
        let started = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.imageTask(with: Test.request)
        await started.wait()

        // WHEN the switch is turned on while it runs
        pipeline.diagnostics.isEnabled = true
        #expect(pipeline.diagnostics.isEnabled)
        dataLoader.isSuspended = false
        _ = try await task.response

        // THEN it isn't recorded, not even partially
        #expect(task.metrics == nil)
    }

    /// The runtime switch pauses a recording the configuration turned on; it
    /// can't start one the configuration left off.
    @Test func switchCannotTurnOnDiagnosticsTheConfigurationLeftOff() async throws {
        // GIVEN
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isDiagnosticsEnabled = false
        }

        // WHEN
        pipeline.diagnostics.isEnabled = true

        // THEN
        #expect(!pipeline.diagnostics.isEnabled)
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response
        #expect(task.metrics == nil)
    }

    @Test func switchIsPerPipeline() async throws {
        // GIVEN two pipelines that record
        let other = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isDiagnosticsEnabled = true
        }

        // WHEN one of them is paused
        pipeline.diagnostics.isEnabled = false

        // THEN the other one still records
        #expect(other.diagnostics.isEnabled)
        let task = other.imageTask(with: Test.request)
        _ = try await task.response
        let metrics = try #require(task.metrics)
        #expect(metrics.pipelineID == other.id)
        #expect(metrics.pipelineID != pipeline.id)
    }

    /// "A task is either recorded in full or not at all", however the switch
    /// flips while the tasks start.
    @Test func switchFlippedWhileTasksStartRecordsEachTaskInFullOrNotAtAll() async throws {
        // GIVEN a switch that keeps flipping
        let pipeline = self.pipeline
        let toggler = Task.detached {
            var isEnabled = true
            while !Task.isCancelled {
                isEnabled.toggle()
                pipeline.diagnostics.isEnabled = isEnabled
                await Task.yield()
            }
        }

        // WHEN tasks that share nothing run meanwhile
        let tasks = (0..<40).map {
            pipeline.imageTask(with: ImageRequest(url: URL(string: "https://example.com/flip-\($0).jpeg")!))
        }
        for task in tasks {
            _ = try await task.response
        }
        toggler.cancel()
        await toggler.value

        // THEN every record there is has the whole chain
        for task in tasks {
            guard let metrics = task.metrics else { continue }
            #expect(metrics.startedAt != nil)
            #expect(metrics.outcome == .success)
            #expect(metrics.jobs.map(\.kind) == [.loadImage, .fetchOriginalImage, .fetchOriginalData])
            #expect(metrics.jobs.allSatisfy { $0.taskIDs == [task.taskId] && $0.createdByTaskID == task.taskId && $0.outcome == .success })
            #expect(metrics.bytes?.downloaded == 22789)
        }
    }

    /// Anything but `0`, `no`, `false`, or nothing at all is on, whatever
    /// the case of the letters.
    @Test func environmentVariableIgnoresCase() {
        for value in ["NO", "No", "FALSE", "False", "fAlSe"] {
            #expect(!ImagePipeline.Diagnostics.isEnabled(in: ["NUKE_DIAGNOSTICS_ENABLED": value]), "\(value)")
        }
        for value in ["true", "TRUE", "yes", "2", "enabled"] {
            #expect(ImagePipeline.Diagnostics.isEnabled(in: ["NUKE_DIAGNOSTICS_ENABLED": value]), "\(value)")
        }
        // Only this variable counts
        #expect(!ImagePipeline.Diagnostics.isEnabled(in: ["NUKE_DIAGNOSTICS": "1", "DIAGNOSTICS_ENABLED": "1"]))
    }

    /// A task recorded after the switch came back on joins work that a task
    /// started while it was off: it is coalesced, and it is the only task the
    /// shared jobs report, since the other one was never recorded.
    @Test func taskJoiningWorkStartedWhileTheSwitchWasOff() async throws {
        // GIVEN a download started by a task that isn't recorded
        pipeline.diagnostics.isEnabled = false
        dataLoader.isSuspended = true
        let started = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let unrecorded = pipeline.imageTask(with: Test.request)
        await started.wait()

        // WHEN a recorded task joins it
        pipeline.diagnostics.isEnabled = true
        let joined = TestExpectation()
        pipeline.onTaskStarted = { _ in joined.fulfill() }
        let recorded = pipeline.imageTask(with: Test.request)
        await joined.wait()
        pipeline.onTaskStarted = nil
        dataLoader.isSuspended = false
        _ = try await unrecorded.response
        _ = try await recorded.response

        // THEN
        #expect(unrecorded.metrics == nil)
        let metrics = try #require(recorded.metrics)
        #expect(metrics.isCoalesced)
        #expect(metrics.jobs.map(\.kind) == [.loadImage, .fetchOriginalImage, .fetchOriginalData])
        #expect(metrics.jobs.allSatisfy { $0.joinedAt != nil })
        #expect(metrics.jobs.allSatisfy { $0.taskIDs == [recorded.taskId] })
        #expect(metrics.sharedTaskIDs.isEmpty)
        #expect(dataLoader.createdTaskCount == 1)
        // The header says the task was coalesced, and with nobody it can name
        #expect(metrics.description.range(of: #"\ncoalesced: +yes\n"#, options: .regularExpression) != nil, "Unexpected header in:\n\(metrics.description)")
    }

    // MARK: - Tasks That Never Started

    /// A task cancelled before the pipeline got to it still finishes with a
    /// record: it waited on nothing, so it has no jobs and no start.
    @Test @ImagePipelineActor func taskCancelledBeforeThePipelineStartedIt() async throws {
        // GIVEN a task cancelled in the same actor turn it was created in,
        // before the pipeline started it
        let task = pipeline.imageTask(with: Test.request)
        task._cancelTask()

        // WHEN
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.outcome == .cancelled)
        #expect(metrics.error == nil)
        #expect(metrics.source == nil)
        #expect(metrics.startedAt == nil)
        #expect(metrics.rootJobID == nil)
        #expect(metrics.jobs.isEmpty)
        #expect(!metrics.isCoalesced)
        #expect(metrics.bytes == nil)
        #expect(metrics.image == nil)
        #expect(metrics.duration >= 0)
        #expect(dataLoader.createdTaskCount == 0)

        // THEN the timeline has no wait to show and no work, only the total
        let timeline = metrics.formatted(.timeline)
        #expect(timeline.split(separator: "\n").count == 1, "Unexpected timeline:\n\(timeline)")
        #expect(timeline.hasPrefix("total "))
        #expect(metrics.description.hasPrefix("ImageTask #\(task.taskId) · cancelled · "))
    }

    @Test func taskOnAnInvalidatedPipelineRecordsTheFailure() async throws {
        // GIVEN an invalidated pipeline, which is known to be invalidated once
        // the task it was running got cancelled
        dataLoader.isSuspended = true
        let started = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let running = pipeline.imageTask(with: Test.request)
        await started.wait()
        pipeline.invalidate()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await running.response
        }

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        await #expect(throws: ImagePipeline.Error.pipelineInvalidated) {
            try await task.response
        }

        // THEN the task failed before the pipeline started it
        let metrics = try #require(task.metrics)
        #expect(metrics.outcome == .failure)
        #expect(metrics.startedAt == nil)
        #expect(metrics.jobs.isEmpty)
        let error = try #require(metrics.error)
        #expect(error.code == "pipelineInvalidated")
        #expect(error.underlyingDomain == nil)
        #expect(error.underlyingCode == nil)

        // THEN the error is the first field of the header
        let lines = metrics.description.split(separator: "\n").map(String.init)
        #expect(lines[1].range(of: #"^error: +pipelineInvalidated · .+$"#, options: .regularExpression) != nil, "Unexpected header in:\n\(metrics.description)")

        // THEN the task that was running is recorded as cancelled
        #expect(running.metrics?.outcome == .cancelled)
    }

    /// A download the task was cancelled out of before `dataLoadingQueue` let
    /// it run, which is what scrolling past the cells does to a busy pipeline,
    /// knows when it was enqueued, and nothing else. The task spent that time
    /// waiting, not on the network.
    @Test @ImagePipelineActor func downloadThatNeverLeftItsQueue() async throws {
        // GIVEN a data loading queue that holds its work
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        defer { queue.isSuspended = false }
        var task: ImageTask?
        _ = await queue.waitForOperations(count: 1) {
            task = pipeline.imageTask(with: Test.request)
        }
        let imageTask = try #require(task)

        // WHEN it is cancelled while it waits
        imageTask.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await imageTask.response
        }

        // THEN the stage says it was queued and never started
        let metrics = try #require(imageTask.metrics)
        #expect(metrics.outcome == .cancelled)
        let fetch = try #require(metrics.jobs.last)
        #expect(fetch.kind == .fetchOriginalData)
        #expect(fetch.outcome == .cancelled)
        let download = try #require(fetch.stages.first)
        #expect(fetch.stages.count == 1)
        #expect(download.kind == .download)
        #expect(download.queuedAt != nil)
        #expect(download.startedAt == nil)
        #expect(download.duration == nil)
        #expect(download.endedAt == nil)
        #expect(download.queueWait == nil)
        #expect(download.attributedDuration == nil)
        #expect(download.bytes == nil)
        #expect(download.source == nil)
        #expect(metrics.bytes == nil)
        #expect(dataLoader.createdTaskCount == 0)

        let line = try #require(metrics.description.split(separator: "\n").first { $0.contains("─ download ") }, "No download in:\n\(metrics.description)")
        #expect(line.hasSuffix("never started"), "Unexpected row: \(line)")

        // THEN the wait is queue time, not network time
        let categories = metrics.timeShares.map(\.category)
        #expect(!categories.contains(.network), "Unexpected shares: \(metrics.timeShares)\n\(metrics.description)")
        #expect(categories.contains(.queue), "No queue share in: \(metrics.timeShares)")
    }

    // MARK: - Waits

    /// A request the rate limiter held is a wait of its own, in front of the
    /// download it held up.
    @Test @ImagePipelineActor func requestHeldByTheRateLimiterIsAWait() async throws {
        // GIVEN a rate limiter with a backlog, which holds the next request
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.dataCache = nil
            $0.isDiagnosticsEnabled = true
        }
        let rateLimiter = try #require(pipeline.rateLimiter)
        let task = pipeline.imageTask(with: Test.request)
        // Runs before the pipeline starts the task: it's the same actor turn
        for _ in 0..<30 {
            rateLimiter.execute { true }
        }

        // WHEN
        _ = try await task.response

        // THEN the wait is a stage that started when the request reached the
        // limiter, and the download was enqueued once it was let through
        let metrics = try #require(task.metrics)
        let fetch = try #require(metrics.jobs.last)
        #expect(fetch.stages.map(\.kind) == [.rateLimit, .download])
        let rateLimit = try #require(fetch.stages.first)
        #expect(rateLimit.queuedAt == nil)
        let startedAt = try #require(rateLimit.startedAt)
        let duration = try #require(rateLimit.duration)
        // The limiter drains its backlog no sooner than 15 ms later
        #expect(duration >= 0.01)
        #expect(startedAt >= fetch.createdAt)
        let download = try #require(fetch.stages.last)
        #expect(try #require(download.queuedAt) >= startedAt + duration - 1e-6)

        // THEN it is a category of its own, and a row of its own above the
        // download (and above the wait for the data loading queue, if the
        // download had to wait for it too)
        let share = try #require(metrics.timeShares.first { $0.category == .rateLimit })
        #expect(abs(share.duration - duration) < 1e-6)
        let lines = metrics.formatted(.timeline).split(separator: "\n").map(String.init)
        let rateLimitRow = try #require(lines.firstIndex { $0.contains("─ rateLimit ") }, "No rateLimit in:\n\(metrics.description)")
        let downloadRow = try #require(lines.firstIndex { $0.contains("─ download ") }, "No download in:\n\(metrics.description)")
        #expect(rateLimitRow < downloadRow, "Unexpected timeline:\n\(metrics.description)")
    }

    // MARK: - Cancellation

    /// "The work that was running is cancelled along with the job": the
    /// download it was waiting on is closed at the cancellation, and says
    /// nothing about bytes it never received.
    @Test func runningDownloadIsClosedWhenTheTaskIsCancelled() async throws {
        // GIVEN a task whose download started and never received anything
        dataLoader.isSuspended = true
        let started = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.imageTask(with: Test.request)
        await started.wait()

        // WHEN
        task.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }

        // THEN
        let metrics = try #require(task.metrics)
        let download = try #require(metrics.jobs.last?.stages.first { $0.kind == .download })
        let startedAt = try #require(download.startedAt)
        let duration = try #require(download.duration)
        #expect(startedAt + duration <= metrics.endedAt)
        #expect(download.attributedDuration == duration)
        #expect(download.firstByteAt == nil)
        #expect(download.bytes == nil)
        #expect(download.source == nil)
        #expect(metrics.bytes == nil)

        // THEN the time the download ran is network time, and the header has
        // no transfer to show
        let network = try #require(metrics.timeShares.first { $0.category == .network })
        #expect(abs(network.duration - duration) < 1e-6)
        let description = metrics.description
        #expect(!description.contains("\ntransfer:"), "Unexpected transfer in:\n\(description)")
        #expect(!description.contains("running"), "Unexpected running row in:\n\(description)")
    }

    /// A task that left work others still needed sees it running.
    @Test func taskThatLeftSharedWorkSeesItRunning() async throws {
        // GIVEN two tasks sharing a download that hasn't completed
        dataLoader.isSuspended = true
        let started = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task1 = pipeline.imageTask(with: Test.request)
        await started.wait()
        let joined = TestExpectation()
        pipeline.onTaskStarted = { _ in joined.fulfill() }
        let task2 = pipeline.imageTask(with: Test.request)
        await joined.wait()
        pipeline.onTaskStarted = nil

        // WHEN the first one leaves
        task1.cancel()
        _ = try? await task1.response
        dataLoader.isSuspended = false
        _ = try await task2.response

        // THEN every job it waited on, and the download, is running in its copy
        let metrics = try #require(task1.metrics)
        #expect(!metrics.isCoalesced)
        #expect(metrics.sharedTaskIDs == [task2.taskId])
        let lines = metrics.formatted(.timeline).split(separator: "\n").map(String.init)
        for job in metrics.jobs {
            let row = try #require(lines.first { $0.contains("j\(job.id) \(job.kind.rawValue)") })
            #expect(row.hasSuffix("  running"), "Unexpected row: \(row)")
        }
        let download = try #require(lines.first { $0.contains("─ download ") })
        #expect(download.hasSuffix("  running"), "Unexpected row: \(download)")
        #expect(metrics.description.range(of: #"\ncoalesced: +no · shared with #\#(task2.taskId) \(j[0-9]+, j[0-9]+, j[0-9]+\)\n"#, options: .regularExpression) != nil, "Unexpected header in:\n\(metrics.description)")
    }

    // MARK: - Failures

    @Test func decodingFailureIsRecordedOnTheJobThatFailed() async throws {
        // GIVEN a decoder that fails
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.makeImageDecoder = { _ in MockFailingDecoder() }
            $0.isDiagnosticsEnabled = true
        }

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try? await task.response

        // THEN the error names the underlying error
        let metrics = try #require(task.metrics)
        #expect(metrics.outcome == .failure)
        let error = try #require(metrics.error)
        #expect(error.code == "decodingFailed")
        #expect(error.underlyingDomain == (MockError(description: "decoder-failed") as NSError).domain)
        #expect(error.description.contains("decoder-failed"))

        // THEN the download that fed the decoder succeeded, and the decode
        // produced nothing
        #expect(metrics.jobs.map(\.kind) == [.loadImage, .fetchOriginalImage, .fetchOriginalData])
        #expect(metrics.jobs.map(\.outcome) == [.failure, .failure, .success])
        #expect(metrics.jobs[1].error?.code == "decodingFailed")
        let decode = try #require(metrics.jobs[1].stages.first { $0.kind == .decode })
        #expect(decode.decoder == "MockFailingDecoder")
        #expect(decode.format == nil)
        #expect(decode.pixels == nil)
        #expect(decode.duration != nil)
        #expect(metrics.bytes?.downloaded == 22789)

        // THEN the job that ended differently from the task says how it ended
        let lines = metrics.description.split(separator: "\n")
        let fetchRow = try #require(lines.first { $0.contains("j\(metrics.jobs[2].id) fetchOriginalData") }, "No fetch in:\n\(metrics.description)")
        #expect(fetchRow.hasSuffix("success"), "Unexpected row: \(fetchRow)")
        let loadRow = try #require(lines.first { $0.contains("j\(metrics.jobs[0].id) loadImage") })
        #expect(!loadRow.contains("failure"), "Unexpected row: \(loadRow)")
    }

    @Test func processingFailureIsRecorded() async throws {
        // GIVEN
        let request = ImageRequest(url: Test.url, processors: [MockFailingProcessor()])

        // WHEN
        let task = pipeline.imageTask(with: request)
        _ = try? await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.outcome == .failure)
        #expect(metrics.error?.code == "processingFailed")
        #expect(metrics.error?.underlyingDomain == (ImageProcessingError.unknown as NSError).domain)
        let process = try #require(metrics.jobs[0].stages.first { $0.kind == .process })
        #expect(process.processor == "MockFailingProcessor")
        #expect(process.pixels == nil)
        #expect(process.isProgressive == false)
        #expect(metrics.jobs[0].outcome == .failure)
        #expect(metrics.jobs.dropFirst().allSatisfy { $0.outcome == .success })
        // Nothing is written to the memory cache for a failure
        #expect(!metrics.jobs[0].stages.contains { $0.kind == .memoryStore })
    }

    @Test func emptyResponseIsRecorded() async throws {
        // GIVEN
        dataLoader.results[Test.url] = .success((Data(), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 0, textEncodingName: nil)))

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try? await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.error?.code == "dataIsEmpty")
        #expect(metrics.error?.underlyingDomain == nil)
        let fetch = try #require(metrics.jobs.last)
        let download = try #require(fetch.stages.first { $0.kind == .download })
        #expect(download.bytes == 0)
        #expect(download.duration != nil)
        #expect(fetch.outcome == .failure)
        #expect(!fetch.stages.contains { $0.kind == .diskStore })
    }

    @Test func dataMissingInCacheIsRecordedWithTheLookups() async throws {
        // GIVEN
        var request = Test.request
        request.options = [.returnCacheDataDontLoad]

        // WHEN
        let task = pipeline.imageTask(with: request)
        _ = try? await task.response

        // THEN the task looked in both caches and went no further
        let metrics = try #require(task.metrics)
        #expect(metrics.error?.code == "dataMissingInCache")
        #expect(metrics.request.options == ["returnCacheDataDontLoad"])
        #expect(metrics.jobs.map(\.kind) == [.loadImage])
        #expect(metrics.jobs[0].stages.map(\.kind) == [.memoryLookup, .diskLookup])
        #expect(metrics.jobs[0].stages.map(\.result) == [.miss, .miss])
        #expect(metrics.bytes == nil)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func missingDecoderIsRecorded() async throws {
        // GIVEN
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.makeImageDecoder = { _ in nil }
            $0.isDiagnosticsEnabled = true
        }

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try? await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.error?.code == "decoderNotRegistered")
        #expect(metrics.error?.underlyingDomain == nil)
        // No decoder, no decode stage
        #expect(!metrics.jobs.flatMap(\.stages).contains { $0.kind == .decode })
    }

    @Test func downloadOverTheSizeLimitIsRecorded() async throws {
        // GIVEN
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.maximumResponseDataSize = 100
            $0.isDiagnosticsEnabled = true
        }

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try? await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.error?.code == "dataDownloadExceededMaximumSize")
        #expect(metrics.error?.underlyingDomain == nil)
        let download = try #require(metrics.jobs.last?.stages.first { $0.kind == .download })
        #expect(download.firstByteAt != nil)
        #expect(download.duration != nil)
        #expect(metrics.jobs.last?.outcome == .failure)
    }

    @Test func delegateThatThrowsBeforeTheDownloadIsRecorded() async throws {
        // GIVEN a delegate that refuses to load the data
        let delegate = MockWillLoadDataDelegate { _ in
            throw URLError(.userAuthenticationRequired)
        }
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isDiagnosticsEnabled = true
        }

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try? await task.response

        // THEN the error is the delegate's
        let metrics = try #require(task.metrics)
        #expect(metrics.error?.code == "dataLoadingFailed")
        #expect(metrics.error?.underlyingDomain == NSURLErrorDomain)
        #expect(metrics.error?.underlyingCode == URLError.userAuthenticationRequired.rawValue)

        // THEN the delegate ran and the download never did
        let fetch = try #require(metrics.jobs.last)
        let willLoadData = try #require(fetch.stages.first { $0.kind == .willLoadData })
        #expect(willLoadData.duration != nil)
        let download = try #require(fetch.stages.first { $0.kind == .download })
        #expect(download.startedAt == nil)
        #expect(download.firstByteAt == nil)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func everyErrorHasTheNameOfItsCase() throws {
        let underlying = URLError(.timedOut)
        let decodingContext = ImageDecodingContext(request: Test.request, data: Test.data)
        let processingContext = ImageProcessingContext(request: Test.request, response: ImageResponse(container: Test.container, request: Test.request), isCompleted: true)
        let errors: [(ImagePipeline.Error, String, Bool)] = [
            (.dataMissingInCache, "dataMissingInCache", false),
            (.dataLoadingFailed(error: underlying), "dataLoadingFailed", true),
            (.dataIsEmpty, "dataIsEmpty", false),
            (.decoderNotRegistered(context: decodingContext), "decoderNotRegistered", false),
            (.decodingFailed(decoder: ImageDecoders.Empty(), context: decodingContext, error: underlying), "decodingFailed", true),
            (.processingFailed(processor: MockFailingProcessor(), context: processingContext, error: underlying), "processingFailed", true),
            (.imageRequestMissing, "imageRequestMissing", false),
            (.pipelineInvalidated, "pipelineInvalidated", false),
            (.dataDownloadExceededMaximumSize, "dataDownloadExceededMaximumSize", false),
            (.cancelled, "cancelled", false)
        ]
        for (error, code, wrapsAnError) in errors {
            let summary = ImagePipeline.Diagnostics.ErrorSummary(error)
            #expect(summary.code == code)
            #expect(summary.description == error.description)
            #expect(summary.underlyingDomain == (wrapsAnError ? NSURLErrorDomain : nil), "\(code)")
            #expect(summary.underlyingCode == (wrapsAnError ? URLError.timedOut.rawValue : nil), "\(code)")
        }
    }

    // MARK: - Sources

    /// A preview found in the memory cache is delivered, but the image the
    /// task finishes with came from the network.
    @Test func previewInTheMemoryCacheIsNotTheSource() async throws {
        // GIVEN
        pipeline.cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.source == .network)
        #expect(metrics.previewCount == 1)
        let lookup = try #require(metrics.jobs[0].stages.first)
        #expect(lookup.kind == .memoryLookup)
        #expect(lookup.result == .hit)
        #expect(lookup.isProgressive == true)
        #expect(dataLoader.createdTaskCount == 1)

        // THEN the header counts the preview and the lookup row says what it found
        let description = metrics.description
        #expect(description.range(of: #"\npreviews: +1\n"#, options: .regularExpression) != nil, "No previews in:\n\(description)")
        let row = try #require(description.split(separator: "\n").first { $0.contains("─ memoryLookup ") })
        #expect(row.contains("hit · preview"), "Unexpected row: \(row)")
    }

    @Test func dataTaskServedFromDiskHasNoImage() async throws {
        // GIVEN
        dataCache.store[pipeline.cache.makeDataCacheKey(for: Test.request)] = Test.data

        // WHEN
        let task = pipeline.makeStartedImageTask(with: Test.request, isDataTask: true)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.kind == .data)
        #expect(metrics.source == .disk)
        #expect(metrics.jobs.map(\.kind) == [.loadData])
        let lookup = try #require(metrics.jobs[0].stages.first)
        #expect(metrics.jobs[0].stages.count == 1)
        #expect(lookup.kind == .diskLookup)
        #expect(lookup.result == .hit)
        #expect(lookup.bytes == Int64(Test.data.count))
        #expect(metrics.bytes == nil)
        #expect(dataLoader.createdTaskCount == 0)

        // THEN the header names the kind, and has no image or transfer to show
        let description = metrics.description
        #expect(description.range(of: #"\nkind: +data\n"#, options: .regularExpression) != nil, "No kind in:\n\(description)")
        #expect(!description.contains("\nimage:"), "Unexpected image in:\n\(description)")
        #expect(!description.contains("\ntransfer:"), "Unexpected transfer in:\n\(description)")
        #expect(description.hasPrefix("ImageTask #\(task.taskId) · success · "))
        #expect(description.split(separator: "\n").first?.hasSuffix("from disk") == true)
    }

    /// A thumbnail request with no processors falls back to the original data
    /// on disk, which is a second lookup under a different key.
    @Test func thumbnailFallsBackToTheOriginalOnDisk() async throws {
        // GIVEN the original data on disk
        dataCache.store[pipeline.cache.makeDataCacheKey(for: Test.request)] = Test.data
        var request = Test.request
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 100)

        // WHEN
        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.source == .disk)
        #expect(metrics.request.thumbnail == request.thumbnail?.identifier)
        let lookups = metrics.jobs[0].stages.filter { $0.kind == .diskLookup }
        #expect(lookups.map(\.result) == [.miss, .hit])
        #expect(lookups.map(\.cacheKey) == [
            diagnosticsDigest(of: pipeline.cache.makeDataCacheKey(for: request)),
            diagnosticsDigest(of: pipeline.cache.makeDataCacheKey(for: Test.request))
        ])
        #expect(lookups[0].cacheKey != lookups[1].cacheKey)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func animatedImageIsDescribedAsAnimated() async throws {
        // GIVEN
        let request = ImageRequest(url: Test.url(forResource: "cat", extension: "gif"))

        // WHEN
        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.source == .file)
        let image = try #require(metrics.image)
        #expect(image.format == "gif")
        #expect(image.isAnimated)
        #expect(image.width > 0 && image.height > 0)
        #expect(metrics.description.range(of: #"\nimage: +[0-9]+×[0-9]+ · gif · animated · .+ in memory\n"#, options: .regularExpression) != nil, "Unexpected image in:\n\(metrics.description)")
    }

    // MARK: - Cache Keys

    /// A write and a lookup of the same entry print the same digest, which
    /// is what makes two records comparable.
    @Test func cacheStagesOfTheSameEntryCarryTheSameDigest() async throws {
        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        let stages = metrics.jobs.flatMap(\.stages)
        let key = { (kind: ImagePipeline.Diagnostics.Stage.Kind) in stages.first { $0.kind == kind }?.cacheKey }
        #expect(key(.memoryLookup) == pipeline.cache.makeImageCacheKeyDigest(for: Test.request))
        #expect(key(.memoryLookup) == key(.memoryStore))
        #expect(key(.diskLookup) == diagnosticsDigest(of: pipeline.cache.makeDataCacheKey(for: Test.request)))
        #expect(key(.diskLookup) == key(.diskStore))
        #expect(key(.memoryLookup) != nil)
        #expect(key(.diskLookup) != nil)
        // The stages that aren't cache stages carry none
        #expect(stages.filter { [.download, .decode, .decompress].contains($0.kind) }.allSatisfy { $0.cacheKey == nil })

        // THEN the digests are printed only when asked for
        let digest = try #require(key(.memoryLookup))
        #expect(metrics.description.contains("key \(digest)"))
        #expect(!metrics.formatted(.all.subtracting(.cacheKeys)).contains(digest))
    }

    // MARK: - Identifiers

    @Test func jobIDsAreUniqueWithinThePipeline() async throws {
        // WHEN two tasks that share nothing
        let task1 = pipeline.imageTask(with: ImageRequest(url: URL(string: "https://example.com/1.jpeg")!))
        _ = try await task1.response
        let task2 = pipeline.imageTask(with: ImageRequest(url: URL(string: "https://example.com/2.jpeg")!))
        _ = try await task2.response

        // THEN
        let ids1 = try #require(task1.metrics).jobs.map(\.id)
        let ids2 = try #require(task2.metrics).jobs.map(\.id)
        #expect(ids1.count == 3)
        #expect(ids2.count == 3)
        #expect(Set(ids1 + ids2).count == 6)
        #expect(!ids1.contains(0))
        #expect(task1.metrics?.rootJobID == ids1.first)
    }

    @Test func labelThatIsNotAStringIsIgnored() async throws {
        // GIVEN
        var request = Test.request
        request.userInfo[.labelKey] = 42

        // WHEN
        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.label == nil)
        #expect(metrics.description.hasPrefix("ImageTask #\(task.taskId) · success"))
    }

    @Test func requestSummaryNamesEveryOption() {
        // GIVEN
        var request = ImageRequest(url: Test.url, processors: [.resize(width: 100), .circle()], priority: .veryHigh)
        request.options = [
            .skipDataLoadingQueue, .skipDecompression, .returnCacheDataDontLoad,
            .disableDiskCacheWrites, .disableDiskCacheReads,
            .disableMemoryCacheWrites, .disableMemoryCacheReads
        ]

        // WHEN
        let summary = ImageTask.Metrics.RequestSummary(request)

        // THEN every option has a name, in the order they are declared
        #expect(summary.options == [
            "disableMemoryCacheReads", "disableMemoryCacheWrites",
            "disableDiskCacheReads", "disableDiskCacheWrites",
            "returnCacheDataDontLoad", "skipDecompression", "skipDataLoadingQueue"
        ])
        #expect(summary.processors == request.processors.map(\.identifier))
        #expect(summary.priority == .veryHigh)
        #expect(summary.url == Test.url.absoluteString)
        #expect(summary.imageID == Test.url.absoluteString)
        #expect(summary.thumbnail == nil)

        // THEN the composite options name their parts
        #expect(ImageRequest.Options.disableMemoryCache.diagnosticsNames == ["disableMemoryCacheReads", "disableMemoryCacheWrites"])
        #expect(ImageRequest.Options.reloadIgnoringCachedData.diagnosticsNames == ["disableMemoryCacheReads", "disableDiskCacheReads"])
        #expect(ImageRequest.Options().diagnosticsNames.isEmpty)
    }

    // MARK: - Memory

    /// The recorder keeps nothing: a task's record is dropped the moment it
    /// becomes the snapshot, and the jobs' records go with the jobs.
    @Test func recordsAreReleasedWithTheWork() async throws {
        // GIVEN a task held in its download, and the records it is building
        dataLoader.isSuspended = true
        let started = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.imageTask(with: ImageRequest(url: Test.url, processors: [.resize(width: 100)]))
        await started.wait()
        let records = await Task { @ImagePipelineActor in
            let record = task._diagnostics
            var jobs: [WeakRef<ImagePipeline.Diagnostics.JobRecord>] = []
            var job = record?.rootJob
            while let current = job {
                jobs.append(WeakRef(current))
                job = current.parent
            }
            return (WeakRef(record), jobs)
        }.value
        #expect(records.0.value != nil)
        #expect(records.1.count == 4)

        // WHEN
        dataLoader.isSuspended = false
        _ = try await task.response

        // THEN the task's record is gone as soon as the task finished
        #expect(records.0.value == nil)
        #expect(await Task { @ImagePipelineActor in task._diagnostics == nil }.value)

        // THEN the jobs' records are released once the jobs finish unwinding
        await waitUntil { records.1.allSatisfy { $0.value == nil } }
        #expect(task.metrics?.jobs.count == 4)
    }
}
