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

        var count = 0
        for await _ in pipeline.diagnostics.events {
            count += 1
        }
        #expect(count == 0)
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
            #expect(unit.peakSubscriberCount == 1)
            #expect(unit.outcome == .success)
            #expect(unit.endedAt != nil)
        }

        // THEN the stages are recorded
        let root = metrics.units[0]
        #expect(root.stages.map(\.kind).filter { $0 != .decompress } == [.memoryLookup, .diskLookup, .memoryStore])
        #expect(root.stages[0].result == .miss)
        #expect(root.stages[1].result == .miss)
        let store = try #require(root.stages.last)
        #expect(store.cost == ImageCache.cost(for: response.container))

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
        #expect(download.chunkCount == 1)
        #expect(download.firstByteAt != nil)
        #expect(download.queuedAt != nil)
        #expect(download.duration != nil)
        #expect(fetch.stages[1].bytes == 22789)

        // THEN the bytes and the image are copied up
        #expect(metrics.bytes?.downloaded == 22789)
        #expect(metrics.bytes?.expected == 22789)
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
        // GIVEN
        let prefetcher = ImagePrefetcher(pipeline: pipeline)
        let events = pipeline.diagnostics.events

        // WHEN
        prefetcher.startPrefetching(with: [Test.url])

        // THEN
        var metrics: ImageTask.Metrics?
        for await event in events {
            if case .taskFinished(let finished) = event {
                metrics = finished
                break
            }
        }
        #expect(metrics?.kind == .prefetch)
        #expect(metrics?.outcome == .success)
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
        #expect((metrics.units[2].stages.first?.chunkCount ?? 0) >= 3)
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

    @Test func encodingIsTrailingWorkOfTheUnit() async throws {
        // GIVEN
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.dataCache = dataCache
            $0.dataCachePolicy = .storeEncodedImages
            $0.isDiagnosticsEnabled = true
        }
        let events = pipeline.diagnostics.events

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response
        let metrics = try #require(task.metrics)

        // THEN the task's copy has the encode queued and never started
        let queued = try #require(metrics.units[0].stages.first { $0.kind == .encode })
        #expect(queued.startedAt == nil)
        #expect(queued.duration == nil)

        // THEN the finished unit has the whole stage
        var finished: ImagePipeline.Diagnostics.Unit?
        for await event in events {
            if case .unitFinished(let unit) = event, unit.id == metrics.rootUnitID {
                finished = unit
                break
            }
        }
        let encode = try #require(finished?.stages.first { $0.kind == .encode })
        #expect(encode.encoder == "ImageEncoders.Default")
        #expect(encode.duration != nil)
        #expect(encode.workDuration != nil)
        #expect((encode.bytes ?? 0) > 0)
        #expect(encode.attributedDuration == nil)
        #expect(finished?.joinedAt == nil)
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
        #expect(creator.units[0].peakSubscriberCount == 2)
        #expect(creator.units[1].peakSubscriberCount == 1)

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
        #expect(joiner.units[1].peakSubscriberCount == 2)
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

    @Test func unitPriorityHistoryNamesTheCause() async throws {
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
        #expect(metrics.priorityHistory.map(\.causeTaskID) == [nil])
        for unit in metrics.units {
            let history = unit.priorityHistory.map { ($0.priority, $0.causeTaskID) }
            #expect(history.map(\.0) == [.low, .high, .low, .veryHigh])
            #expect(history.map(\.1) == [task1.taskId, task2.taskId, task2.taskId, task1.taskId])
        }
    }

    // MARK: - Events

    @Test func eventsAreStreamedInOrder() async throws {
        // GIVEN
        let events = pipeline.diagnostics.events

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response
        let metrics = try #require(task.metrics)

        // THEN
        var recorded: [ImagePipeline.Diagnostics.Event] = []
        for await event in events {
            recorded.append(event)
            if case .taskFinished = event {
                break
            }
        }
        #expect(recorded.map(\.name) == [
            "taskCreated", "taskStarted",
            "unitCreated", "unitCreated", "unitCreated",
            "unitFinished", "unitFinished", "unitFinished",
            "taskFinished"
        ])
        guard case .taskCreated(let created) = recorded[0],
              case .taskStarted(let started) = recorded[1],
              case .taskFinished(let finished) = recorded[8] else {
            Issue.record("Unexpected events: \(recorded)")
            return
        }
        #expect(created.taskID == task.taskId)
        #expect(created.createdAt == metrics.createdAt)
        #expect(started.rootUnitID == metrics.rootUnitID)
        #expect(!started.didJoin)
        #expect(finished.taskID == task.taskId)

        // THEN the units are created dependency first and named by their parent
        let createdUnits = recorded.compactMap { event -> ImagePipeline.Diagnostics.Event.UnitCreated? in
            if case .unitCreated(let unit) = event { return unit }
            return nil
        }
        #expect(createdUnits.map(\.id) == metrics.units.reversed().map(\.id))
        #expect(createdUnits.map(\.parentID) == metrics.units.reversed().map(\.parentID))
        #expect(createdUnits.allSatisfy { $0.createdByTaskID == task.taskId })
    }

    @Test func joiningTaskReportsTheJoin() async throws {
        // GIVEN
        let events = pipeline.diagnostics.events
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: Test.request), pipeline.imageTask(with: Test.request))
        }
        _ = try await task1.response
        _ = try await task2.response

        // THEN one task joined, and the units were created once
        var starts: [ImagePipeline.Diagnostics.Event.TaskStarted] = []
        var unitsCreated = 0
        var tasksFinished = 0
        for await event in events {
            switch event {
            case .taskStarted(let started): starts.append(started)
            case .unitCreated: unitsCreated += 1
            case .taskFinished: tasksFinished += 1
            default: break
            }
            if tasksFinished == 2 {
                break
            }
        }
        #expect(Set(starts.map(\.didJoin)) == [false, true])
        #expect(Set(starts.map(\.rootUnitID)).count == 1)
        #expect(unitsCreated == 3)
    }

    @Test func observerReceivesTheEventsSynchronously() async throws {
        // GIVEN
        let observer = _EventCollector()
        pipeline.diagnostics.addObserver(observer)

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // THEN the observer saw the terminal event by the time the task finished
        let names = await observer.events.map(\.name)
        #expect(names.first == "taskCreated")
        #expect(names.contains("taskFinished"))

        // WHEN the observer is removed
        pipeline.diagnostics.removeObserver(observer)
        _ = try await pipeline.imageTask(with: Test.request).response

        // THEN it receives nothing else
        #expect(await observer.events.count == names.count)
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

        // THEN the last two tasks and their units are retained
        #expect(trace.schemaVersion == ImagePipeline.Diagnostics.schemaVersion)
        #expect(trace.pipelineID == pipeline.id)
        #expect(trace.tasks.map(\.taskID) == Array(taskIDs.suffix(2)))
        let retainedUnitIDs = Set(trace.tasks.flatMap { $0.units.map(\.id) })
        #expect(Set(trace.units.map(\.id)) == retainedUnitIDs)
        #expect(trace.units.allSatisfy { $0.outcome == .success && $0.joinedAt == nil })

        // THEN the summary adds it up
        let summary = trace.summary()
        #expect(summary.tasks == 2)
        #expect(summary.succeeded == 2)
        #expect(summary.failed == 0)
        #expect(summary.cancelled == 0)
        #expect(summary.source == ["network": 2])
        #expect(summary.coalescing.coalescedTasks == 0)
        #expect(summary.coalescing.sharedUnits == 0)
        #expect(summary.stages["download"]?.count == 2)
        #expect(summary.stages["decode"]?.count == 2)
        #expect(summary.stages["download"]?.queueWaitP95 != nil)
        #expect(summary.stages["memoryLookup"]?.queueWaitP95 == nil)
        #expect(summary.bytes.downloaded == 2 * 22789)
        #expect(summary.configuration.isTaskCoalescingEnabled)
        #expect(summary.configuration.imageDecodingQueue == 1)
        #expect(summary.configuration.dataCachePolicy == "storeOriginalData")
        #expect(summary.configuration.hasDataCache)
    }

    @Test func nothingIsRetainedByDefault() async throws {
        _ = try await pipeline.imageTask(with: Test.request).response
        let trace = await pipeline.diagnostics.export()
        #expect(trace.tasks.isEmpty)
        #expect(trace.units.isEmpty)
        #expect(trace.summary().tasks == 0)
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

    @Test func eventsEncodeWithTheirName() async throws {
        // GIVEN
        let started = ImagePipeline.Diagnostics.Event.taskStarted(.init(taskID: 7, startedAt: 1, rootUnitID: 3, didJoin: true))

        // WHEN
        let data = try JSONEncoder().encode(started)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // THEN the payload is flattened next to the name
        #expect(object["event"] as? String == "taskStarted")
        #expect(object["schemaVersion"] as? Int == ImagePipeline.Diagnostics.schemaVersion)
        #expect(object["taskID"] as? Int == 7)
        #expect(object["didJoin"] as? Bool == true)

        // THEN it decodes back
        guard case .taskStarted(let decoded) = try JSONDecoder().decode(ImagePipeline.Diagnostics.Event.self, from: data) else {
            Issue.record("Unexpected event")
            return
        }
        #expect(decoded.rootUnitID == 3)

        // THEN a finished task nests its record
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response
        let finished = try JSONEncoder().encode(ImagePipeline.Diagnostics.Event.taskFinished(try #require(task.metrics)))
        let finishedObject = try #require(JSONSerialization.jsonObject(with: finished) as? [String: Any])
        #expect(finishedObject["event"] as? String == "taskFinished")
        #expect((finishedObject["metrics"] as? [String: Any])?["taskID"] as? UInt64 == task.taskId)
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
        #expect(metrics.description.contains("ImageTask #42 · prefetch · low"))

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
            try JSONDecoder().decode(ImagePipeline.Diagnostics.Event.self, from: Data(#"{"event":"teleported","schemaVersion":1}"#.utf8))
        }
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

        // THEN
        #expect(description.hasPrefix("ImageTask #\(task.taskId) · image · normal · "))
        #expect(description.contains("· success · source: network · avatar"))
        #expect(description.contains("coalesced: no"))
        #expect(description.contains("u\(task.metrics!.rootUnitID!) · loadImage [\(request.processors[0].identifier)]"))
        for stage in ["memoryLookup", "diskLookup", "download", "decode", "process", "memoryStore"] {
            #expect(description.contains(stage), "Missing \(stage) in:\n\(description)")
        }
        #expect(description.hasSuffix("finished"))
    }
}

@ImagePipelineActor
private final class _EventCollector: ImagePipeline.Diagnostics.Observer {
    var events: [ImagePipeline.Diagnostics.Event] = []

    nonisolated init() {}

    func pipeline(_ pipeline: ImagePipeline, didRecord event: ImagePipeline.Diagnostics.Event) {
        events.append(event)
    }
}

private final class _SlowDelegate: ImagePipeline.Delegate, Sendable {
    @ImagePipelineActor
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        try await Task.sleep(for: .milliseconds(25))
        return urlRequest
    }
}
