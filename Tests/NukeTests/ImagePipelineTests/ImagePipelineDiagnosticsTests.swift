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

        // THEN the chain of units is recorded, root first
        #expect(metrics.units.map(\.kind) == [.loadImage, .fetchOriginalImage, .fetchOriginalData])
        #expect(metrics.rootUnitID == metrics.units[0].id)
        #expect(metrics.units.map(\.parentID) == [metrics.units[1].id, metrics.units[2].id, nil])
        for unit in metrics.units {
            #expect(unit.createdByTaskID == task.taskId)
            #expect(unit.taskIDs == [task.taskId])
            #expect(unit.joinedAt == nil)
            #expect(unit.outcome == .success)
            #expect(unit.endedAt != nil)
        }

        // THEN the stages are recorded
        let root = metrics.units[0]
        #expect(root.stages.map(\.kind).filter { $0 != .decompress } == [.memoryLookup, .diskLookup, .memoryStore])
        #expect(root.stages[0].result == .miss)
        #expect(root.stages[1].result == .miss)

        let decode = try #require(metrics.units[1].stages.first)
        #expect(metrics.units[1].stages.count == 1)
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

        let fetch = metrics.units[2]
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

    @Test func memoryHitIsOneUnitAndOneStage() async throws {
        // GIVEN
        pipeline.cache[Test.request] = Test.container

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.source == .memory)
        #expect(metrics.units.count == 1)
        #expect(metrics.units[0].stages.map(\.kind) == [.memoryLookup])
        #expect(metrics.units[0].stages[0].result == .hit)
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
        #expect(metrics.units.map(\.kind) == [.loadImage])
        let stages = metrics.units[0].stages
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
        let kinds = metrics.units.flatMap(\.stages).map(\.kind)
        #expect(!kinds.contains(.memoryLookup))
        #expect(!kinds.contains(.diskLookup))
        #expect(!kinds.contains(.memoryStore))
        #expect(!kinds.contains(.diskStore))
    }

    @Test func processorAddsAUnitAndAStage() async throws {
        // GIVEN
        let processor = ImageProcessors.Resize(size: CGSize(width: 320, height: 240), unit: .pixels)
        let request = ImageRequest(url: Test.url, processors: [processor])

        // WHEN
        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.request.processors == [processor.identifier])
        #expect(metrics.units.map(\.kind) == [.loadImage, .loadImage, .fetchOriginalImage, .fetchOriginalData])
        #expect(metrics.units[0].processors == [processor.identifier])
        #expect(metrics.units[1].processors == [])
        let process = try #require(metrics.units[0].stages.first { $0.kind == .process })
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
        let fetch = try #require(metrics.units.last)
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
        let fetch = try #require(metrics.units.last)
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
        #expect(metrics.units.map(\.kind) == [.loadImage, .fetchOriginalImage])
        let download = try #require(metrics.units[1].stages.first)
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

        let fetch = try #require(metrics.units.last)
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
        #expect(metrics.units.count == 3)
        for unit in metrics.units {
            #expect(unit.outcome == .cancelled)
            #expect(unit.endedAt != nil)
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
        #expect(metrics.units.map(\.kind) == [.loadData, .fetchOriginalData])
        #expect(metrics.units[0].stages.map(\.kind) == [.diskLookup])
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
        let decodes = metrics.units[1].stages.filter { $0.kind == .decode }
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
        let fetch = try #require(metrics.units.last)
        #expect(Set(fetch.stages.map(\.kind)) == [.willLoadData, .download])
        let willLoadData = try #require(fetch.stages.first { $0.kind == .willLoadData }?.duration)
        #expect(willLoadData >= 0.02)
        // The download is enqueued before the delegate runs, so its wait
        // includes the delegate.
        let queueWait = try #require(fetch.stages.first { $0.kind == .download }?.queueWait)
        #expect(queueWait >= 0.02)
        #expect(metrics.description.range(of: "willLoadData")!.lowerBound < metrics.description.range(of: "download ")!.lowerBound)
    }

    // MARK: - Coalescing

    @Test func coalescedTaskJoinsTheUnits() async throws {
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

        // THEN they carry the same units
        #expect(creator.units.count == 3)
        #expect(creator.units.map(\.id) == joiner.units.map(\.id))
        #expect(creator.rootUnitID == joiner.rootUnitID)
        #expect(creator.sharedTaskIDs == [joiner.taskID])
        #expect(joiner.sharedTaskIDs == [creator.taskID])

        // THEN the join is recorded on the edge
        #expect(creator.units.allSatisfy { $0.joinedAt == nil })
        #expect(joiner.units.allSatisfy { $0.joinedAt != nil })
        for (unit, copy) in zip(creator.units, joiner.units) {
            #expect(unit.createdByTaskID == creator.taskID)
            #expect(unit.taskIDs == [creator.taskID, joiner.taskID])
            #expect(copy.taskIDs == unit.taskIDs)
            #expect(unit.stages.count == copy.stages.count)
        }

        // THEN the attributed durations are clamped to the task
        for unit in joiner.units {
            for stage in unit.stages {
                guard let attributed = stage.attributedDuration, let duration = stage.duration else { continue }
                #expect(attributed <= duration + 0.0001)
                #expect(attributed <= joiner.duration + 0.0001)
            }
        }
        let lookups = joiner.units[0].stages.filter { $0.kind == .memoryLookup || $0.kind == .diskLookup }
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
        #expect(metrics1.units.count == 4)
        #expect(metrics1.units[0].id != metrics2.units[0].id)
        #expect(metrics1.units.dropFirst().map(\.id) == metrics2.units.dropFirst().map(\.id))

        let (creator, joiner) = metrics1.isCoalesced ? (metrics2, metrics1) : (metrics1, metrics2)
        #expect(!creator.isCoalesced)
        #expect(joiner.isCoalesced)
        #expect(joiner.units[0].joinedAt == nil)
        #expect(joiner.units.dropFirst().allSatisfy { $0.joinedAt != nil })
        #expect(joiner.units[1].taskIDs == [creator.taskID, joiner.taskID])
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
        #expect(imageMetrics.units.last?.kind == .fetchOriginalData)
        #expect(imageMetrics.units.last?.id == dataMetrics.units.last?.id)
        #expect(imageMetrics.units.last?.taskIDs.count == 2)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func cancellingOneOfTwoTasksLeavesTheUnitRunning() async throws {
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
        #expect(metrics1.units.allSatisfy { $0.outcome == nil && $0.endedAt == nil })

        let metrics2 = try #require(task2.metrics)
        #expect(metrics2.outcome == .success)
        #expect(metrics2.units.allSatisfy { $0.outcome == .success })
        #expect(metrics2.units[0].taskIDs == [task1.taskId, task2.taskId])
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func unitPriorityHistoryFollowsTheTasks() async throws {
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

        // THEN every unit records the escalation, the demotion, and the change
        let metrics = try #require(task1.metrics)
        #expect(metrics.priorityHistory.map(\.priority) == [.veryHigh])
        for unit in metrics.units {
            #expect(unit.priorityHistory.map(\.priority) == [.low, .high, .low, .veryHigh])
        }
    }

    // MARK: - Export

    @Test func exportRetainsTheLastTasks() async throws {
        // GIVEN
        pipeline.diagnostics.retainedTaskCount = 2
        #expect(pipeline.diagnostics.retainedTaskCount == 2)
        let requests = (1...3).map { ImageRequest(url: URL(string: "http://test.com/\($0).jpeg")!) }

        // WHEN
        var taskIDs: [UInt64] = []
        for request in requests {
            let task = pipeline.imageTask(with: request)
            _ = try await task.response
            taskIDs.append(task.taskId)
        }
        let trace = await pipeline.diagnostics.export()

        // THEN the last two tasks are retained
        #expect(trace.schemaVersion == ImagePipeline.Diagnostics.schemaVersion)
        #expect(trace.pipelineID == pipeline.id)
        #expect(trace.tasks.map(\.taskID) == Array(taskIDs.suffix(2)))

        // THEN the trace names the configuration that explains them
        #expect(trace.configuration.isTaskCoalescingEnabled)
        #expect(trace.configuration.imageDecodingQueue == 1)
        #expect(trace.configuration.dataCachePolicy == "storeOriginalData")
        #expect(trace.configuration.hasDataCache)
    }

    @Test func nothingIsRetainedByDefault() async throws {
        _ = try await pipeline.imageTask(with: Test.request).response
        let trace = await pipeline.diagnostics.export()
        #expect(trace.tasks.isEmpty)
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
        #expect(decoded.units.map(\.id) == metrics.units.map(\.id))
        #expect(decoded.units.flatMap(\.stages).map(\.kind) == metrics.units.flatMap(\.stages).map(\.kind))
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
        #expect(metrics.schemaVersion == 1)
        #expect(metrics.taskID == 42)
        #expect(metrics.kind == .prefetch)
        #expect(metrics.label == "feed")
        #expect(metrics.isCoalesced)
        #expect(metrics.units.count == 3)
        #expect(metrics.units[0].joinedAt == 1788606000.1202)
        let download = try #require(metrics.units[2].stages.first { $0.kind == .download })
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
        #expect(metrics.description.hasPrefix("ImageTask #42 \"feed\" · success · 366.3 ms · from network\n"))
        #expect(metrics.description.range(of: #"\ncoalesced: +yes · shared with #41 \(u6, u7, u8\)\n"#, options: .regularExpression) != nil)

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

    @Test func descriptionPrintsTheTimeline() async throws {
        // GIVEN
        var request = ImageRequest(url: Test.url, processors: [.resize(width: 100)])
        request.userInfo[.labelKey] = "avatar"

        // WHEN
        let task = pipeline.imageTask(with: request)
        _ = try await task.response
        let description = try #require(task.metrics).description

        // THEN the header is a title, then a field per fact with the values in a column
        let header = description.split(separator: "\n", omittingEmptySubsequences: false).prefix { !$0.isEmpty }
        let title = #"^ImageTask #\#(task.taskId) "avatar" · success · [0-9.]+ ms · from network$"#
        #expect(header.first?.range(of: title, options: .regularExpression) != nil, "No title in:\n\(description)")
        let fields = [
            "kind: +image",
            "url: +\(NSRegularExpression.escapedPattern(for: Test.url.absoluteString))",
            "processors: +\(NSRegularExpression.escapedPattern(for: request.processors[0].identifier))",
            "priority: +normal",
            "image: +[0-9]+×[0-9]+ · jpeg",
            "download: +[0-9.,]+ [a-zA-Z]+",
            "coalesced: +no",
            "pipeline: +\(task.metrics!.pipelineID.uuidString)"
        ]
        for field in fields {
            #expect(header.contains { $0.range(of: "^\(field)$", options: .regularExpression) != nil }, "Missing \(field) in:\n\(description)")
        }
        let valueColumns = header.dropFirst().compactMap { line in
            line.range(of: #"^[a-zA-Z]+: +"#, options: .regularExpression).map { line[..<$0.upperBound].count }
        }
        #expect(valueColumns.count == header.count - 1)
        #expect(Set(valueColumns).count == 1, "Misaligned header in:\n\(description)")

        // THEN the units form a tree, root first, with the durations in a column
        #expect(description.contains("\nu\(task.metrics!.rootUnitID!) loadImage [resize]\n├─ memoryLookup "))
        #expect(description.contains("\n│     └─ decode "))
        #expect(description.contains("\n└─ memoryStore "))
        for stage in ["diskLookup", "download", "process"] {
            #expect(description.contains("─ \(stage) "), "Missing \(stage) in:\n\(description)")
        }
        let lines = description.split(separator: "\n")
        let pattern = #"^([│ ]*[├└]─ [a-zA-Z]+|started|finished) +[0-9.]+ ms"#
        let columns = lines.compactMap { line in
            line.range(of: pattern, options: .regularExpression).map { line[..<$0.upperBound].count }
        }
        #expect(columns.count >= 8)
        #expect(Set(columns).count == 1, "Misaligned durations in:\n\(description)")
        #expect(lines.last?.hasPrefix("finished ") == true)

        // THEN the first and the last row carry the time of day
        let clock = #"^(started|finished) +[0-9.]+ ms   (█+  )?at [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}$"#
        #expect(lines.first { $0.hasPrefix("started") }?.range(of: clock, options: .regularExpression) != nil)
        #expect(lines.last?.range(of: clock, options: .regularExpression) != nil)
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
        let process = try #require(task.metrics?.units.first?.stages.first { $0.kind == .process })
        let printed = try #require(Double(lines[index][waitRange].dropLast(3)))
        let queueWait = try #require(process.queueWait)
        #expect(abs(printed - queueWait * 1000) < 0.1)
    }

    @Test func formattedPicksTheSections() async throws {
        // GIVEN a record with a download `URLSession` measured
        let metrics = try JSONDecoder().decode(ImageTask.Metrics.self, from: Test.data(name: "diagnostics-metrics", extension: "json"))

        // WHEN
        let header = metrics.formatted(.header)
        let timeline = metrics.formatted(.timeline)
        let urlSession = metrics.formatted(.urlSessionTimeline)

        // THEN every section stands on its own
        #expect(header.hasPrefix("ImageTask #42 \"feed\" · success"))
        #expect(header.range(of: #"\npipeline: +3B0C6E4A-6D5C-4F0E-9E43-2C7D1A9B5F10$"#, options: .regularExpression) != nil, "Unexpected header:\n\(header)")
        #expect(timeline.hasPrefix("started "))
        #expect(timeline.contains("\nu6 loadImage"))
        #expect(timeline.hasSuffix("\n") == false && timeline.split(separator: "\n").last?.hasPrefix("finished ") == true)
        #expect(urlSession.hasPrefix("URLSessionTask #17 · "))

        // THEN the description is every section, in order, a blank line apart
        #expect(metrics.description == [header, timeline, urlSession].joined(separator: "\n\n"))
        #expect(metrics.formatted([.header, .urlSessionTimeline]) == header + "\n\n" + urlSession)

        // THEN a task without a download `URLSession` measured has no section for it
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response
        let recorded = try #require(task.metrics)
        #expect(recorded.formatted(.urlSessionTimeline).isEmpty)
        #expect(recorded.description == recorded.formatted([.header, .timeline]))
    }

    @Test func descriptionPrintsTheURLSessionTimeline() throws {
        // GIVEN a download that was redirected once
        let metrics = try JSONDecoder().decode(ImageTask.Metrics.self, from: Test.data(name: "diagnostics-metrics", extension: "json"))

        // WHEN
        let section = metrics.formatted(.urlSessionTimeline)
        let lines = section.split(separator: "\n")

        // THEN the title names the task, and the first and the last row carry the time of day
        #expect(lines.first == "URLSessionTask #17 · 410.7 ms · 1 redirect")
        let clock = #"^(started|finished) +[0-9.]+ ms   (█+  )?at [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}$"#
        #expect(lines[1].range(of: clock, options: .regularExpression) != nil, "No clock in:\n\(section)")
        #expect(lines[1].hasPrefix("started "))
        #expect(lines[1].contains(" 0.3 ms "))
        #expect(lines.last?.range(of: clock, options: .regularExpression) != nil, "No clock in:\n\(section)")
        #expect(lines.last?.hasPrefix("finished ") == true)

        // THEN every request is a heading: the request, the response, the connection, the network
        #expect(section.contains("\nnetworkLoad · https://cdn.example.com/photos/1024.jpg · HTTP 301 · h2 · TLS 1.3 · reused connection · 151.101.1.1 · sent 412 bytes · received 318 bytes\n├─ request "), "Unexpected section:\n\(section)")
        #expect(section.contains("\nnetworkLoad · https://img.example.com/photos/1024.jpg · HTTP 200 · h2 · TLS 1.3 · 151.101.2.2 · sent 398 bytes · received 1.2 MB · cellular · expensive\n├─ blocked "), "Unexpected section:\n\(section)")

        // THEN the steps are under it, in order, the waits light, and the wait for a connection only when it is worth a row
        let pattern = #"^[├└]─ ([a-zA-Z]+) +([0-9.]+) ms(?:   ([█░]+))?$"#
        let steps: [[String]] = lines.compactMap { line in
            guard let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: String(line), range: NSRange(line.startIndex..., in: line)) else { return nil }
            return (1...3).map { index in
                Range(match.range(at: index), in: line).map { String(line[$0]) } ?? ""
            }
        }
        #expect(steps == [
            ["request", "0.1", ""], ["waiting", "37.5", "░░"], ["response", "0.2", ""],
            ["blocked", "1.4", ""], ["domainLookup", "3.2", ""], ["connect", "10.1", ""], ["secureConnection", "20.0", ""], ["request", "0.3", ""], ["waiting", "18.8", ""], ["response", "318.0", String(repeating: "█", count: 15)]
        ], "Unexpected steps in:\n\(section)")
        #expect(lines.filter { $0.hasPrefix("└─ ") }.count == 2)

        // THEN the durations are in a column
        let columns = lines.compactMap { line in
            line.range(of: #"^([├└]─ [a-zA-Z]+|started|finished) +[0-9.]+ ms"#, options: .regularExpression).map { line[..<$0.upperBound].count }
        }
        #expect(columns.count == 12)
        #expect(Set(columns).count == 1, "Misaligned durations in:\n\(section)")
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
        let download = try #require(metrics.units.last?.stages.first { $0.kind == .download })
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

        // THEN the description has a section for it
        let taskID = try #require(download.urlSessionTaskID)
        #expect(metrics.description.contains("\n\nURLSessionTask #\(taskID) · "))
        #expect(metrics.formatted(.urlSessionTimeline).contains("\n\(transaction.fetchType.rawValue) · \(url.absoluteString)\n"), "Unexpected section:\n\(metrics.formatted(.urlSessionTimeline))")
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
