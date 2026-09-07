// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDiagnosticsTests {
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

    // MARK: - Switches

    @Test func nothingIsRecordedByDefault() async throws {
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        #expect(task.metrics == nil)
        #expect(!pipeline.diagnostics.isEnabled)
    }

    @Test func runtimeSwitchTurnsTheRecordingOff() async throws {
        #expect(pipeline.diagnostics.isEnabled)

        pipeline.diagnostics.isEnabled = false
        let task1 = pipeline.imageTask(with: Test.request)
        _ = try await task1.response
        #expect(task1.metrics == nil)

        pipeline.diagnostics.isEnabled = true
        let task2 = pipeline.imageTask(with: Test.request)
        _ = try await task2.response
        #expect(task2.metrics != nil)
    }

    // MARK: - Sources and Stages

    @Test func networkLoadRecordsTheWholeChain() async throws {
        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        let response = try await task.response

        // THEN the task is described
        let metrics = try #require(task.metrics)
        #expect(metrics.schemaVersion == ImagePipeline.Diagnostics.schemaVersion)
        #expect(metrics.pipelineID == pipeline.id)
        #expect(metrics.taskID == task.taskId)
        #expect(metrics.kind == .image)
        #expect(metrics.label == nil)
        #expect(metrics.request.url == Test.url.absoluteString)
        #expect(metrics.request.priority == .normal)
        #expect(metrics.outcome == .success)
        #expect(metrics.error == nil)
        #expect(metrics.source == .network)
        #expect(!metrics.isCoalesced)
        #expect(metrics.previewCount == 0)
        #expect(metrics.priorityHistory.isEmpty)
        #expect(metrics.duration > 0)
        let startedAt = try #require(metrics.startedAt)
        #expect(metrics.createdAt <= startedAt)
        #expect(startedAt <= metrics.endedAt)
        #expect(abs((metrics.endedAt - metrics.createdAt) - metrics.duration) < 0.001)

        // THEN the chain of jobs is recorded, root first
        #expect(metrics.jobs.map(\.kind) == [.loadImage, .fetchOriginalImage, .fetchOriginalData])
        #expect(metrics.rootJobID == metrics.jobs[0].id)
        #expect(metrics.jobs.map(\.parentID) == [metrics.jobs[1].id, metrics.jobs[2].id, nil])
        for job in metrics.jobs {
            #expect(job.createdByTaskID == task.taskId)
            #expect(job.taskIDs == [task.taskId])
            #expect(job.joinedAt == nil)
            #expect(job.outcome == .success)
            #expect(job.endedAt != nil)
        }

        // THEN the stages are recorded
        let root = metrics.jobs[0]
        #expect(root.stages.map(\.kind).filter { $0 != .decompress } == [.memoryLookup, .diskLookup, .memoryStore])
        #expect(root.stages[0].result == .miss)
        #expect(root.stages[1].result == .miss)

        let decode = try #require(metrics.jobs[1].stages.first)
        #expect(metrics.jobs[1].stages.count == 1)
        #expect(decode.kind == .decode)
        #expect(decode.decoder == "ImageDecoders.Default")
        #expect(decode.format == "jpeg")
        #expect(decode.pixels == .init(width: 640, height: 480))
        #expect(decode.isProgressive == false)
        // `ImageDecoders.Default` decodes on the actor: Image I/O is lazy.
        #expect(decode.queuedAt == nil)
        let workDuration = try #require(decode.workDuration)
        let duration = try #require(decode.duration)
        #expect(workDuration <= duration)
        #expect(decode.attributedDuration == duration)

        let fetch = metrics.jobs[2]
        #expect(fetch.stages.map(\.kind) == [.download, .diskStore])
        let download = fetch.stages[0]
        #expect(download.source == .network)
        #expect(download.bytes == 22789)
        #expect(download.resumedBytes == 0)
        #expect(download.expectedBytes == 22789)
        #expect(download.firstByteAt != nil)
        #expect(download.queuedAt != nil)
        #expect(download.duration != nil)
        #expect(fetch.stages[1].bytes == 22789)

        // THEN the bytes and the image are copied up
        #expect(metrics.bytes?.downloaded == 22789)
        #expect(metrics.bytes?.expected == 22789)

        // THEN there is nothing from `URLSession`: the loader is a mock
        #expect(metrics.urlSessionMetrics == nil)
        #expect(metrics.image?.width == 640)
        #expect(metrics.image?.height == 480)
        #expect(metrics.image?.format == "jpeg")
        #expect(metrics.image?.isAnimated == false)
    }

    @Test func memoryHitIsOneJobAndOneStage() async throws {
        // GIVEN
        pipeline.cache[Test.request] = Test.container

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.source == .memory)
        #expect(metrics.jobs.count == 1)
        #expect(metrics.jobs[0].stages.map(\.kind) == [.memoryLookup])
        #expect(metrics.jobs[0].stages[0].result == .hit)
        #expect(metrics.bytes == nil)
        #expect(metrics.image?.width == 640)
    }

    @Test func diskHitShowsTheLookupAndTheDecode() async throws {
        // GIVEN
        dataCache.store[pipeline.cache.makeDataCacheKey(for: Test.request)] = Test.data

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.source == .disk)
        #expect(metrics.jobs.map(\.kind) == [.loadImage])
        let stages = metrics.jobs[0].stages
        #expect(stages.map(\.kind).filter { $0 != .decompress } == [.memoryLookup, .diskLookup, .decode, .memoryStore])
        #expect(stages[1].result == .hit)
        #expect(stages[1].bytes == Int64(Test.data.count))
        #expect(stages[2].format == "jpeg")
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func lookupsAreRecordedOnlyForTheCachesThatExist() async throws {
        // GIVEN a pipeline with no caches
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isDiagnosticsEnabled = true
        }

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        let kinds = metrics.jobs.flatMap(\.stages).map(\.kind)
        #expect(!kinds.contains(.memoryLookup))
        #expect(!kinds.contains(.diskLookup))
        #expect(!kinds.contains(.memoryStore))
        #expect(!kinds.contains(.diskStore))
    }

    @Test func processorAddsAJobAndAStage() async throws {
        // GIVEN
        let processor = ImageProcessors.Resize(size: CGSize(width: 320, height: 240), unit: .pixels)
        let request = ImageRequest(url: Test.url, processors: [processor])

        // WHEN
        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.request.processors == [processor.identifier])
        #expect(metrics.jobs.map(\.kind) == [.loadImage, .loadImage, .fetchOriginalImage, .fetchOriginalData])
        #expect(metrics.jobs[0].processors == [processor.identifier])
        #expect(metrics.jobs[1].processors == [])
        let process = try #require(metrics.jobs[0].stages.first { $0.kind == .process })
        #expect(process.processor == processor.identifier)
        #expect(process.pixels == .init(width: 320, height: 240))
        #expect(process.isProgressive == false)
        #expect(process.workDuration != nil)
        #expect(metrics.image?.width == 320)
    }

    @Test func localFileSetsTheSource() async throws {
        // GIVEN
        let request = ImageRequest(url: Test.url(forResource: "fixture", extension: "jpeg"))

        // WHEN
        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.source == .file)
        let fetch = try #require(metrics.jobs.last)
        #expect(fetch.kind == .fetchOriginalData)
        #expect(fetch.stages.map(\.kind) == [.download])
        #expect(fetch.stages[0].source == .file)
        #expect(fetch.stages[0].bytes == Int64(Test.data.count))
        #expect(metrics.bytes?.downloaded == Int64(Test.data.count))
    }

    @Test func dataClosureSetsTheSource() async throws {
        // GIVEN
        let request = ImageRequest(id: "closure", data: { Test.data })

        // WHEN
        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.request.url == nil)
        #expect(metrics.request.imageID == "closure")
        #expect(metrics.source == .closure)
        let fetch = try #require(metrics.jobs.last)
        #expect(fetch.kind == .fetchOriginalData)
        let download = try #require(fetch.stages.first { $0.kind == .download })
        #expect(download.source == .closure)
        #expect(download.bytes == Int64(Test.data.count))
    }

    @Test func imageClosureSetsTheSource() async throws {
        // GIVEN
        let request = ImageRequest(id: "closure", image: { Test.container })

        // WHEN
        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.source == .closure)
        #expect(metrics.jobs.map(\.kind) == [.loadImage, .fetchOriginalImage])
        let download = try #require(metrics.jobs[1].stages.first)
        #expect(download.kind == .download)
        #expect(download.source == .closure)
        #expect(download.pixels == .init(width: 640, height: 480))
    }

    @Test func failureCarriesTheErrorCode() async throws {
        // GIVEN
        dataLoader.results[Test.url] = .failure(URLError(.notConnectedToInternet) as NSError)

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try? await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.outcome == .failure)
        #expect(metrics.source == nil)
        #expect(metrics.image == nil)
        let error = try #require(metrics.error)
        #expect(error.code == "dataLoadingFailed")
        #expect(error.underlyingDomain == NSURLErrorDomain)
        #expect(error.underlyingCode == URLError.notConnectedToInternet.rawValue)
        #expect(!error.description.isEmpty)

        let fetch = try #require(metrics.jobs.last)
        #expect(fetch.outcome == .failure)
        #expect(fetch.error?.code == "dataLoadingFailed")
        #expect(fetch.stages.map(\.kind) == [.download])
        #expect(fetch.stages[0].source == .network)
        #expect(fetch.stages[0].duration != nil)
    }

    @Test func cancellationIsRecorded() async throws {
        // GIVEN a task whose download never completes
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
        #expect(metrics.outcome == .cancelled)
        #expect(metrics.error == nil)
        #expect(metrics.source == nil)
        #expect(metrics.jobs.count == 3)
        for job in metrics.jobs {
            #expect(job.outcome == .cancelled)
            #expect(job.endedAt != nil)
        }
    }

    @Test func labelIsRecorded() async throws {
        // GIVEN
        var request = Test.request
        request.userInfo[.labelKey] = "feed"

        // WHEN
        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        // THEN
        #expect(task.metrics?.label == "feed")
    }

    @Test func dataTaskIsRecorded() async throws {
        // WHEN
        let task = pipeline.makeStartedImageTask(with: Test.request, isDataTask: true)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.kind == .data)
        #expect(metrics.source == .network)
        #expect(metrics.jobs.map(\.kind) == [.loadData, .fetchOriginalData])
        #expect(metrics.jobs[0].stages.map(\.kind) == [.diskLookup])
        #expect(metrics.bytes?.downloaded == 22789)
    }

    @Test func prefetchTasksAreTagged() async throws {
        // GIVEN a delegate that picks the records up, the way a logger would
        let delegate = _MetricsCollector()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isDiagnosticsEnabled = true
        }
        let prefetcher = ImagePrefetcher(pipeline: pipeline)

        // WHEN
        prefetcher.startPrefetching(with: [Test.url])
        let metrics = await delegate.nextFinished()

        // THEN
        #expect(metrics.kind == .prefetch)
        #expect(metrics.outcome == .success)
        withExtendedLifetime(prefetcher) {}
    }

    @Test func progressiveDecodingCountsThePreviews() async throws {
        // GIVEN
        let dataLoader = MockProgressiveDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.isDiagnosticsEnabled = true
        }

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        for try await _ in task.previews {
            dataLoader.resume()
        }
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.previewCount == 2)
        let decodes = metrics.jobs[1].stages.filter { $0.kind == .decode }
        #expect(decodes.filter { $0.isProgressive == true }.count == 2)
        #expect(decodes.filter { $0.isProgressive == false }.count == 1)
    }

    @Test func willLoadDataIsRecordedForCustomDelegates() async throws {
        // GIVEN
        let pipeline = ImagePipeline(delegate: _SlowDelegate()) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isDiagnosticsEnabled = true
        }

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        let fetch = try #require(metrics.jobs.last)
        #expect(Set(fetch.stages.map(\.kind)) == [.willLoadData, .download])
        let willLoadData = try #require(fetch.stages.first { $0.kind == .willLoadData }?.duration)
        #expect(willLoadData >= 0.02)
        // The download is enqueued before the delegate runs, so its wait
        // includes the delegate.
        let queueWait = try #require(fetch.stages.first { $0.kind == .download }?.queueWait)
        #expect(queueWait >= 0.02)
        // THEN the rows read in the order the work ran: the download is
        // enqueued first, the delegate runs once the queue admits it, and the
        // download follows
        let labels = ["dataLoadingQueue", "willLoadData", "download"]
        let order = metrics.description.split(separator: "\n").compactMap { line in
            labels.first { line.contains("─ \($0) ") }
        }
        #expect(order == labels, "Unexpected order in:\n\(metrics.description)")
    }

    // MARK: - Coalescing

    @Test func coalescedTaskJoinsTheJobs() async throws {
        // GIVEN two tasks for the same request
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: Test.request), pipeline.imageTask(with: Test.request))
        }
        _ = try await task1.response
        _ = try await task2.response

        // THEN one of them started the work and the other joined it
        let metrics1 = try #require(task1.metrics)
        let metrics2 = try #require(task2.metrics)
        let (creator, joiner) = metrics1.isCoalesced ? (metrics2, metrics1) : (metrics1, metrics2)
        #expect(!creator.isCoalesced)
        #expect(joiner.isCoalesced)
        #expect(dataLoader.createdTaskCount == 1)

        // THEN they carry the same jobs
        #expect(creator.jobs.count == 3)
        #expect(creator.jobs.map(\.id) == joiner.jobs.map(\.id))
        #expect(creator.rootJobID == joiner.rootJobID)
        #expect(creator.sharedTaskIDs == [joiner.taskID])
        #expect(joiner.sharedTaskIDs == [creator.taskID])

        // THEN the join is recorded on the edge
        #expect(creator.jobs.allSatisfy { $0.joinedAt == nil })
        #expect(joiner.jobs.allSatisfy { $0.joinedAt != nil })
        for (job, copy) in zip(creator.jobs, joiner.jobs) {
            #expect(job.createdByTaskID == creator.taskID)
            #expect(job.taskIDs == [creator.taskID, joiner.taskID])
            #expect(copy.taskIDs == job.taskIDs)
            #expect(job.stages.count == copy.stages.count)
        }

        // THEN the attributed durations are clamped to the task
        for job in joiner.jobs {
            for stage in job.stages {
                guard let attributed = stage.attributedDuration, let duration = stage.duration else { continue }
                #expect(attributed <= duration + 0.0001)
                #expect(attributed <= joiner.duration + 0.0001)
            }
        }
        let lookups = joiner.jobs[0].stages.filter { $0.kind == .memoryLookup || $0.kind == .diskLookup }
        #expect(lookups.allSatisfy { $0.attributedDuration == 0 })
    }

    @Test func coalescingWithDifferentProcessorsSharesTheOriginal() async throws {
        // GIVEN
        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "2")])

        // WHEN
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: request1), pipeline.imageTask(with: request2))
        }
        _ = try await task1.response
        _ = try await task2.response

        // THEN the roots differ and the rest is shared
        let metrics1 = try #require(task1.metrics)
        let metrics2 = try #require(task2.metrics)
        #expect(metrics1.jobs.count == 4)
        #expect(metrics1.jobs[0].id != metrics2.jobs[0].id)
        #expect(metrics1.jobs.dropFirst().map(\.id) == metrics2.jobs.dropFirst().map(\.id))

        let (creator, joiner) = metrics1.isCoalesced ? (metrics2, metrics1) : (metrics1, metrics2)
        #expect(!creator.isCoalesced)
        #expect(joiner.isCoalesced)
        #expect(joiner.jobs[0].joinedAt == nil)
        #expect(joiner.jobs.dropFirst().allSatisfy { $0.joinedAt != nil })
        #expect(joiner.jobs[1].taskIDs == [creator.taskID, joiner.taskID])
    }

    @Test func dataTaskAndImageTaskShareTheDownload() async throws {
        // WHEN
        let (imageTask, dataTask) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: Test.request), pipeline.makeStartedImageTask(with: Test.request, isDataTask: true))
        }
        _ = try await imageTask.response
        _ = try await dataTask.response

        // THEN
        let imageMetrics = try #require(imageTask.metrics)
        let dataMetrics = try #require(dataTask.metrics)
        #expect(imageMetrics.jobs.last?.kind == .fetchOriginalData)
        #expect(imageMetrics.jobs.last?.id == dataMetrics.jobs.last?.id)
        #expect(imageMetrics.jobs.last?.taskIDs.count == 2)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func cancellingOneOfTwoTasksLeavesTheJobRunning() async throws {
        // GIVEN two tasks sharing a download that hasn't completed
        dataLoader.isSuspended = true
        let started = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task1 = pipeline.imageTask(with: Test.request)
        await started.wait()
        let task2 = pipeline.imageTask(with: Test.request)
        await Task { @ImagePipelineActor in }.value

        // WHEN
        task1.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task1.response
        }
        dataLoader.isSuspended = false
        _ = try await task2.response

        // THEN
        let metrics1 = try #require(task1.metrics)
        #expect(metrics1.outcome == .cancelled)
        #expect(metrics1.jobs.allSatisfy { $0.outcome == nil && $0.endedAt == nil })

        let metrics2 = try #require(task2.metrics)
        #expect(metrics2.outcome == .success)
        #expect(metrics2.jobs.allSatisfy { $0.outcome == .success })
        #expect(metrics2.jobs[0].taskIDs == [task1.taskId, task2.taskId])
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func jobPriorityHistoryFollowsTheTasks() async throws {
        // GIVEN a low priority task that a high priority one joins
        dataLoader.isSuspended = true
        let started = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task1 = pipeline.imageTask(with: ImageRequest(url: Test.url, priority: .low))
        await started.wait()
        let task2 = pipeline.imageTask(with: ImageRequest(url: Test.url, priority: .high))
        await Task { @ImagePipelineActor in }.value

        // WHEN the high priority task leaves and the low priority one changes
        task2.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task2.response
        }
        task1.priority = .veryHigh
        await Task { @ImagePipelineActor in }.value
        dataLoader.isSuspended = false
        _ = try await task1.response

        // THEN every job records the escalation, the demotion, and the change
        let metrics = try #require(task1.metrics)
        #expect(metrics.priorityHistory.map(\.priority) == [.veryHigh])
        for job in metrics.jobs {
            #expect(job.priorityHistory.map(\.priority) == [.low, .high, .low, .veryHigh])
        }
    }

    // MARK: - Codable

    @Test func metricsRoundTripThroughJSON() async throws {
        // GIVEN
        let request = ImageRequest(url: Test.url, processors: [.resize(width: 100)], priority: .high)
        let task = pipeline.imageTask(with: request)
        _ = try await task.response
        let metrics = try #require(task.metrics)

        // WHEN
        let data = try JSONEncoder().encode(metrics)
        let decoded = try JSONDecoder().decode(ImageTask.Metrics.self, from: data)

        // THEN
        #expect(decoded.taskID == metrics.taskID)
        #expect(decoded.pipelineID == metrics.pipelineID)
        #expect(decoded.request.priority == .high)
        #expect(decoded.request.processors == metrics.request.processors)
        #expect(decoded.jobs.map(\.id) == metrics.jobs.map(\.id))
        #expect(decoded.jobs.flatMap(\.stages).map(\.kind) == metrics.jobs.flatMap(\.stages).map(\.kind))
        #expect(decoded.duration == metrics.duration)
        #expect(decoded.image?.width == metrics.image?.width)

        // THEN the optionals are omitted and the timestamps are plain numbers
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["label"] == nil)
        #expect(object["error"] == nil)
        #expect(object["createdAt"] as? Double == metrics.createdAt)
        #expect(object["outcome"] as? String == "success")
        #expect(object["source"] as? String == "network")
    }

    @Test func goldenFixtureRoundTrips() throws {
        // GIVEN the fixture that pins the schema
        let data = Test.data(name: "diagnostics-metrics", extension: "json")

        // WHEN
        let metrics = try JSONDecoder().decode(ImageTask.Metrics.self, from: data)

        // THEN
        #expect(metrics.schemaVersion == 2)
        #expect(metrics.taskID == 42)
        #expect(metrics.kind == .prefetch)
        #expect(metrics.label == "feed")
        #expect(metrics.isCoalesced)
        #expect(metrics.jobs.count == 3)
        #expect(metrics.jobs[0].joinedAt == 1788606000.1202)
        let download = try #require(metrics.jobs[2].stages.first { $0.kind == .download })
        #expect(download.attributedDuration == 0.2938)
        #expect(download.urlSessionTaskID == 17)
        let urlSession = try #require(download.urlSessionMetrics)
        #expect(urlSession.urlSessionTaskID == 17)
        #expect(metrics.urlSessionMetrics?.urlSessionTaskID == 17)
        #expect(urlSession.redirectCount == 1)
        #expect(urlSession.transactions.map(\.statusCode) == [301, 200])
        #expect(urlSession.transactions.map(\.fetchType) == [.networkLoad, .networkLoad])
        #expect(urlSession.transactions[0].domainLookupStartedAt == nil)
        #expect(urlSession.transactions[1].domainLookupStartedAt == 1788606000.043)
        #expect(metrics.image?.memoryCost == 48_771_072)
        #expect(metrics.jobs[0].stages.first?.cacheKey == "4f2a91c3")
        #expect(metrics.description.hasPrefix("ImageTask #42 \"feed\" · success · 366.3 ms · from network\n"))
        #expect(metrics.description.range(of: #"\ncoalesced: +yes · shared with #41 \(j6, j7, j8\)\n"#, options: .regularExpression) != nil)

        // THEN encoding it again produces the same JSON
        let encoded = try JSONEncoder().encode(metrics)
        let lhs = try #require(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        let rhs = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        #expect(lhs == rhs)
    }

    @Test func unknownNamesDecodeAsUnknown() throws {
        let stage = try JSONDecoder().decode(ImagePipeline.Diagnostics.Stage.self, from: Data(#"{"kind":"teleport","startedAt":1,"duration":0.5}"#.utf8))
        #expect(stage.kind == .unknown)
        #expect(stage.duration == 0.5)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ImageRequest.Priority.self, from: Data(#""urgent""#.utf8))
        }
    }

    // MARK: - Description

    @Test func descriptionPrintsTheHeader() async throws {
        // GIVEN
        var request = ImageRequest(url: Test.url, processors: [.resize(width: 100)])
        request.userInfo[.labelKey] = "avatar"

        // WHEN
        let task = pipeline.imageTask(with: request)
        _ = try await task.response
        let metrics = try #require(task.metrics)
        let description = metrics.description

        // THEN the header is a title, then a field per fact with the values in a column
        let header = description.split(separator: "\n", omittingEmptySubsequences: false).prefix { !$0.isEmpty }
        let title = #"^ImageTask #\#(task.taskId) "avatar" · success · [0-9.]+ ms · from network$"#
        #expect(header.first?.range(of: title, options: .regularExpression) != nil, "No title in:\n\(description)")
        let fields = [
            "url: +\(NSRegularExpression.escapedPattern(for: Test.url.absoluteString))",
            "processors: +\(NSRegularExpression.escapedPattern(for: request.processors[0].identifier))",
            "priority: +normal",
            "image: +[0-9]+×[0-9]+ · jpeg · [0-9.,]+ [a-zA-Z]+ in memory",
            "transfer: +[0-9.,]+ [a-zA-Z]+",
            "pipeline: +\(String(metrics.pipelineID.uuidString.prefix(8)))",
            "time: +[a-z]+ [0-9.]+ ms.*"
        ]
        for field in fields {
            #expect(header.contains { $0.range(of: "^\(field)$", options: .regularExpression) != nil }, "Missing \(field) in:\n\(description)")
        }
        let valueColumns = header.dropFirst().compactMap { line in
            line.range(of: #"^[a-zA-Z]+: +"#, options: .regularExpression).map { line[..<$0.upperBound].count }
        }
        #expect(valueColumns.count == header.count - 1)
        #expect(Set(valueColumns).count == 1, "Misaligned header in:\n\(description)")

        // THEN a fact that says nothing has no field: the usual kind of task,
        // and a task nothing coalesced with
        #expect(!description.contains("\nkind:"))
        #expect(!description.contains("\ncoalesced:"))
        #expect(!description.contains(metrics.pipelineID.uuidString))
    }

    @Test func descriptionPrintsTheTimeline() async throws {
        // WHEN
        let task = pipeline.imageTask(with: ImageRequest(url: Test.url, processors: [.resize(width: 100)]))
        _ = try await task.response
        let metrics = try #require(task.metrics)
        let description = metrics.description

        // THEN the jobs form a tree, root first, with the durations in a column
        #expect(description.contains("\nj\(metrics.rootJobID!) loadImage [resize] "))
        #expect(description.contains("\n├─ memoryLookup "))
        #expect(description.contains("\n│     └─ decode "))
        #expect(description.contains("\n└─ memoryStore "))
        for stage in ["diskLookup", "download", "process"] {
            #expect(description.contains("─ \(stage) "), "Missing \(stage) in:\n\(description)")
        }

        // THEN every row that carries a time carries it in the same column
        let lines = metrics.formatted(.all.subtracting([.header, .breakdown])).split(separator: "\n").map(String.init)
        let columns = lines.compactMap { line in
            line.range(of: #"^.*?  +(–|<0\.1 ms|[0-9.]+ ms)"#, options: .regularExpression).map { line[..<$0.upperBound].count }
        }
        #expect(columns.count >= 8)
        #expect(Set(columns).count == 1, "Misaligned durations in:\n\(description)")

        // THEN the first row is the wait before the pipeline started the task,
        // and the last one is the length of the task, both with the time of day
        let clock = #"(started|finished) at [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}$"#
        #expect(lines.first?.hasPrefix("pending ") == true, "Unexpected first row in:\n\(description)")
        #expect(lines.first?.range(of: clock, options: .regularExpression) != nil, "No clock in:\n\(description)")
        #expect(lines.last?.hasPrefix("total ") == true, "Unexpected last row in:\n\(description)")
        #expect(lines.last?.range(of: clock, options: .regularExpression) != nil, "No clock in:\n\(description)")

        // THEN no row is rounded to a zero that isn't one
        #expect(description.range(of: #"(^|[^0-9.])0\.0 ms"#, options: [.regularExpression]) == nil, "Rounded to zero in:\n\(description)")
    }

    @Test func headerListsTheOptionsAndThePriorityChanges() async throws {
        // GIVEN a task held in its download
        dataLoader.isSuspended = true
        let started = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        var request = ImageRequest(url: Test.url, priority: .low)
        request.options = [.skipDecompression, .disableDiskCacheWrites]
        let task = pipeline.imageTask(with: request)
        await started.wait()

        // WHEN its priority is raised while it waits
        task.priority = .high
        await Task { @ImagePipelineActor in }.value
        dataLoader.isSuspended = false
        _ = try await task.response
        let description = try #require(task.metrics).description

        // THEN
        #expect(description.range(of: #"\noptions: +disableDiskCacheWrites, skipDecompression\n"#, options: .regularExpression) != nil, "No options in:\n\(description)")
        #expect(description.range(of: #"\npriority: +low → high at [0-9.]+ ms\n"#, options: .regularExpression) != nil, "No priority change in:\n\(description)")
    }

    @Test func queueWaitIsARowOfItsOwn() async throws {
        // GIVEN a processing queue that holds its work
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true
        defer { queue.isSuspended = false }

        // WHEN
        let task = pipeline.imageTask(with: ImageRequest(url: Test.url, processors: [.resize(width: 100)]))
        let response = Task { try await task.response }
        try await Task.sleep(for: .milliseconds(50))
        queue.isSuspended = false
        _ = try await response.value
        let description = try #require(task.metrics).description

        // THEN the wait is a row above the stage, named after the queue
        let lines = description.split(separator: "\n")
        let index = try #require(lines.firstIndex { $0.contains("├─ imageProcessingQueue ") }, "No queue row in:\n\(description)")
        #expect(lines[index + 1].contains("─ process "))
        let waitRange = try #require(lines[index].range(of: #"[0-9.]+ ms"#, options: .regularExpression))
        let process = try #require(task.metrics?.jobs.first?.stages.first { $0.kind == .process })
        let printed = try #require(Double(lines[index][waitRange].dropLast(3)))
        let queueWait = try #require(process.queueWait)
        #expect(abs(printed - queueWait * 1000) < 0.1)

        // THEN the wait is its own category in the breakdown
        #expect(description.range(of: #"\ntime: +.*queue [0-9.]+ ms"#, options: .regularExpression) != nil, "No queue share in:\n\(description)")
    }

    @Test func breakdownAddsUpToTheTask() async throws {
        // WHEN
        let task = pipeline.imageTask(with: ImageRequest(url: Test.url, processors: [.resize(width: 100)]))
        _ = try await task.response
        let metrics = try #require(task.metrics)

        // THEN the shares partition the task: nothing is counted twice, and
        // what the stages don't account for lands in `other`
        let shares = metrics.timeShares
        #expect(shares.contains { $0.category == .network })
        #expect(shares.last?.category == .other)
        #expect(abs(shares.map(\.duration).reduce(0, +) - metrics.duration) < 1e-9)
        #expect(abs(shares.map(\.share).reduce(0, +) - 1) < 1e-6)
        for (lhs, rhs) in zip(shares, shares.dropFirst()) where rhs.category != .other {
            #expect(lhs.duration >= rhs.duration, "Unsorted shares: \(shares)")
        }
    }

    @Test func optionsPickWhatIsPrinted() throws {
        // GIVEN a record with a download `URLSession` measured
        let metrics = try JSONDecoder().decode(ImageTask.Metrics.self, from: Test.data(name: "diagnostics-metrics", extension: "json"))

        // THEN the sections stand on their own, and `description` is all of them
        let head = metrics.formatted(.all.subtracting([.timeline, .urlSession]))
        let timeline = metrics.formatted(.all.subtracting([.header, .breakdown]))
        #expect(head.hasPrefix("ImageTask #42 \"feed\" · success"))
        #expect(head.range(of: #"\npipeline: +3B0C6E4A\ntime: +network "#, options: .regularExpression) != nil, "Unexpected header:\n\(head)")
        #expect(timeline.hasPrefix("pending "))
        #expect(timeline.split(separator: "\n").last?.hasPrefix("total ") == true)
        #expect(metrics.description == head + "\n\n" + timeline)
        #expect(!metrics.formatted(.header).contains("\ntime:"))
        #expect(metrics.formatted(.breakdown).range(of: #"^time: +network "#, options: .regularExpression) != nil)
        #expect(!metrics.formatted(.breakdown).contains("\n"))
        #expect(metrics.formatted([]).isEmpty)

        // THEN the columns come off one at a time
        let clock = #"at [0-9]{2}:[0-9]{2}:[0-9]{2}"#
        #expect(metrics.description.range(of: clock, options: .regularExpression) != nil)
        let columns: [(ImageTask.Metrics.Options, String)] = [(.chart, "█"), (.percentages, "%"), (.cacheKeys, "key 4f2a91c3"), (.urlSession, "networkLoad")]
        for (option, sample) in columns {
            let without = metrics.formatted(.all.subtracting(option))
            #expect(metrics.description.contains(sample), "Missing \(sample) in:\n\(metrics.description)")
            #expect(!without.contains(sample), "Unexpected \(sample) in:\n\(without)")
        }
        #expect(metrics.formatted(.all.subtracting(.timestamps)).range(of: clock, options: .regularExpression) == nil)
        #expect(!metrics.formatted(.all.subtracting(.chart)).contains("░"))
        #expect(!metrics.formatted(.all.subtracting(.urlSession)).contains("session #17"))

        // THEN `.plain` is the sections with none of the columns
        #expect(metrics.formatted(.plain) == metrics.formatted(.all.subtracting([.urlSession, .chart, .percentages, .timestamps, .cacheKeys])))
    }

    @Test func chartCellsGoToTheRowThatCoversThem() throws {
        // GIVEN a record whose rows follow one another closely
        let metrics = try JSONDecoder().decode(ImageTask.Metrics.self, from: Test.data(name: "diagnostics-metrics-revalidated", extension: "json"))
        let description = metrics.description
        let lines = description.split(separator: "\n").map(String.init)

        // The first row past `start` that says `needle`. A label repeats from
        // one request to the next, so a chain of rows is looked up in order.
        func row(_ needle: String, from start: Int = 0) throws -> Int {
            try #require(lines[start...].firstIndex { $0.contains(needle) }, "No \(needle) in:\n\(description)")
        }
        // The cell edges a row draws between: a bar runs from the left edge of
        // its first cell to the right edge of its last, and a row too short
        // for a cell is a point on one of the edges. Every label is padded to
        // the same width, so the edges compare across rows.
        func edges(_ index: Int) throws -> ClosedRange<Int> {
            let line = lines[index]
            let offset = { line.distance(from: line.startIndex, to: $0) }
            if let bar = line.range(of: #"[█░]+"#, options: .regularExpression) {
                return offset(bar.lowerBound)...offset(bar.upperBound)
            }
            let mark = try #require(line.firstIndex { $0 == "▏" || $0 == "▕" }, "Nothing drawn in:\n\(line)")
            let edge = offset(mark) + (line[mark] == "▕" ? 1 : 0)
            return edge...edge
        }

        // THEN work that merely follows other work is never drawn before the
        // work it came after ended, the marks of the sub-cell rows included
        let chains = [
            ["─ blocked ", "─ domainLookup ", "─ connect ", "─ secureConnection ", "─ request ", "─ waiting ", "─ response "],
            ["─ decode ", "─ decompress ", "─ memoryStore "]
        ]
        for chain in chains {
            var start = 0
            for (before, after) in zip(chain, chain.dropFirst()) {
                start = try row(before, from: start)
                let (lhs, rhs) = (try edges(start), try edges(try row(after, from: start + 1)))
                #expect(lhs.upperBound <= rhs.lowerBound, "\(before)\(lhs) outruns \(after)\(rhs) in:\n\(description)")
            }
        }

        // THEN a bar is as wide as the row's share of the task, to the cell
        for needle in ["j1 loadImage", "─ download ", "─ connect ", "480.2 ms", "─ decompress "] {
            let line = lines[try row(needle)]
            let value = try #require(line.range(of: #"[0-9.]+(?= ms)"#, options: .regularExpression))
            let duration = try #require(Double(line[value]))
            let cells = Double(try edges(try row(needle)).count - 1)
            let exact = duration / 1000 / metrics.duration * 20
            #expect(abs(cells - exact) <= 1, "\(needle)draws \(cells) cells for \(exact) in:\n\(description)")
        }
    }

    @Test func timelineNestsTheURLSessionRequests() throws {
        // GIVEN a download the session answered out of its `URLCache`, after
        // revalidating it with a request the server answered `304`
        let metrics = try JSONDecoder().decode(ImageTask.Metrics.self, from: Test.data(name: "diagnostics-metrics-revalidated", extension: "json"))
        let description = metrics.description
        let lines = description.split(separator: "\n").map(String.init)

        // THEN the requests sit under the download that made them, indented
        // past it, each with its steps under it
        let download = try #require(lines.firstIndex { $0.contains("─ download ") }, "No download in:\n\(description)")
        #expect(lines[download].contains("session #1"))
        let indent = { (line: String) in line.prefix { $0 == "│" || $0 == " " }.count }
        #expect(indent(lines[download + 1]) > indent(lines[download]))

        let rows = lines[download...].compactMap { line -> String? in
            guard let range = line.range(of: #"[├└]─ [a-zA-Z]+ +(–|<0\.1 ms|[0-9.]+ ms)"#, options: .regularExpression) else { return nil }
            return line[range].dropFirst(3).split(separator: " ", maxSplits: 1).joined(separator: " ").replacing(#/ +/#, with: " ")
        }
        #expect(Array(rows.prefix(13)) == [
            "download 667.7 ms",
            "localCache 6.6 ms", "request <0.1 ms", "waiting 6.6 ms", "response <0.1 ms",
            "networkLoad 658.7 ms", "blocked 17.6 ms", "domainLookup <0.1 ms", "connect 134.0 ms",
            "secureConnection 26.0 ms", "request 0.1 ms", "waiting 480.2 ms", "response 0.6 ms"
        ], "Unexpected rows in:\n\(description)")

        // THEN a request to the URL of the task doesn't repeat it, and the
        // waits are the light part of the chart
        #expect(lines.filter { $0.contains(metrics.request.url!) }.count == 1)
        #expect(try #require(lines.first { $0.contains("480.2 ms") }).contains("░"), "No light bar in:\n\(description)")
    }

    @Test func aRequestTheSessionTimedNothingForSaysSo() throws {
        // GIVEN a `URLCache` hit with no timestamps on it, the way the
        // session reports one it answered without fetching anything
        let data = try Test.data(name: "diagnostics-metrics-revalidated", extension: "json")
        var text = try #require(String(data: data, encoding: .utf8))
        let hit = try #require(text.range(of: #"\{[^{}]*"fetchType": "localCache"[^{}]*\}"#, options: .regularExpression))
        text.replaceSubrange(hit, with: text[hit].replacing(#/,\s+"[a-zA-Z]+At": [0-9.]+/#, with: ""))
        let metrics = try JSONDecoder().decode(ImageTask.Metrics.self, from: Data(text.utf8))

        // THEN the request keeps its row, and says why it has no time on it
        // rather than borrowing the reason a coalesced task has
        let description = metrics.description
        let line = try #require(description.split(separator: "\n").first { $0.contains("localCache") }, "No localCache in:\n\(description)")
        #expect(line.contains("HTTP 200 · not timed"), "Unexpected row in:\n\(description)")
        #expect(!description.contains("before join"))
        #expect(metrics.isServedFromHTTPCache)
    }

    @Test func aURLCacheHitIsNotReportedAsANetworkLoad() throws {
        // GIVEN the same record: 325 KB delivered, 392 bytes on the wire
        let metrics = try JSONDecoder().decode(ImageTask.Metrics.self, from: Test.data(name: "diagnostics-metrics-revalidated", extension: "json"))

        // THEN
        #expect(metrics.source == .httpCache)
        #expect(metrics.isServedFromHTTPCache)
        #expect(metrics.isRevalidated)
        #expect(metrics.wireBytes == 392)
        #expect(metrics.urlSessionMetrics?.networkBytesSent == 216)

        // THEN the header says so, rather than calling 325 KB a download
        let description = metrics.description
        #expect(description.hasPrefix("ImageTask #1 · success · 755.8 ms · from httpCache\n"))
        #expect(description.range(of: #"\ntransfer: +325 KB · 392 bytes on the wire · revalidated\n"#, options: .regularExpression) != nil, "Unexpected transfer in:\n\(description)")
        #expect(description.range(of: #"\nimage: +1440×960 · jpeg · 5.5 MB in memory\n"#, options: .regularExpression) != nil, "Unexpected image in:\n\(description)")

        // THEN the breakdown names the download as the part worth fixing
        #expect(description.range(of: #"\ntime: +network 667.7 ms \(88%\) · decompress 47.7 ms \(6%\) · decode 36.4 ms \(5%\)"#, options: .regularExpression) != nil, "Unexpected breakdown in:\n\(description)")
    }

    // MARK: - URLSession

    @Test func urlSessionMetricsAreRecordedForDataLoader() async throws {
        // GIVEN a pipeline on `DataLoader`, with the session served by a
        // protocol of its own
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [_FixtureURLProtocol.self]
        let pipeline = ImagePipeline {
            $0.dataLoader = DataLoader(configuration: configuration)
            $0.imageCache = nil
            $0.dataCache = nil
            $0.isDiagnosticsEnabled = true
        }
        let url = URL(string: "fixture://diagnostics/image.jpeg")!

        // WHEN
        let task = pipeline.imageTask(with: url)
        _ = try await task.response

        // THEN the download is recorded the way the session saw it. A custom
        // protocol gets one transaction with the request and the time the
        // fetch started, and nothing about the response.
        let metrics = try #require(task.metrics)
        let download = try #require(metrics.jobs.last?.stages.first { $0.kind == .download })
        let urlSession = try #require(download.urlSessionMetrics)
        #expect(urlSession.urlSessionTaskID == download.urlSessionTaskID)
        #expect(metrics.urlSessionMetrics?.urlSessionTaskID == urlSession.urlSessionTaskID)
        #expect(urlSession.startedAt <= urlSession.endedAt)
        #expect(urlSession.startedAt >= metrics.createdAt - 0.001)
        #expect(urlSession.endedAt <= metrics.endedAt + 0.001)
        #expect(urlSession.redirectCount == 0)
        let transaction = try #require(urlSession.transactions.first)
        #expect(urlSession.transactions.count == 1)
        #expect(transaction.url == url.absoluteString)
        #expect(transaction.fetchStartedAt != nil)

        // THEN the request is a row under the download that made it, and it
        // doesn't repeat the URL the header already carries
        let taskID = try #require(download.urlSessionTaskID)
        let description = metrics.description
        let lines = description.split(separator: "\n").map(String.init)
        let index = try #require(lines.firstIndex { $0.contains("─ download ") }, "No download in:\n\(description)")
        #expect(lines[index].contains("session #\(taskID)"))
        #expect(lines[index + 1].contains("─ \(transaction.fetchType.rawValue)"), "Unexpected row in:\n\(description)")
        #expect(lines.filter { $0.contains(url.absoluteString) }.count == 1)
        #expect(!metrics.formatted(.all.subtracting(.urlSession)).contains(transaction.fetchType.rawValue))
    }
}

/// Serves the fixture image to every request of its scheme, so the session
/// takes the metrics of a real task without a network.
private final class _FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "fixture"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(Test.data.count)"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Test.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Receives the records the way a logger would: from the delegate, with the
/// terminal event.
@ImagePipelineActor
private final class _MetricsCollector: ImagePipeline.Delegate {
    private var finished: [ImageTask.Metrics] = []
    private var waiter: CheckedContinuation<ImageTask.Metrics, Never>?

    nonisolated init() {}

    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        guard case .finished = event, let metrics = task.metrics else { return }
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: metrics)
        } else {
            finished.append(metrics)
        }
    }

    /// The next record, in the order the tasks finished.
    func nextFinished() async -> ImageTask.Metrics {
        if !finished.isEmpty {
            return finished.removeFirst()
        }
        return await withCheckedContinuation { waiter = $0 }
    }
}

private final class _SlowDelegate: ImagePipeline.Delegate, Sendable {
    @ImagePipelineActor
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        try await Task.sleep(for: .milliseconds(25))
        return urlRequest
    }
}
