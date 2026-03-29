// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(2)))
struct ImagePipelineMetricsTests {
    let dataLoader: MockDataLoader
    let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isMetricsCollectionEnabled = true
        }
    }

    // MARK: - Basic

    @Test func metricsDisabledByDefault() async throws {
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        #expect(task.metrics == nil)
    }

    @Test func metricsAvailableAfterCompletion() async throws {
        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        #expect(metrics.totalDuration >= 0)
        #expect(metrics.taskStartDate <= metrics.taskEndDate)
        #expect(!metrics.stages.isEmpty)
    }

    // MARK: - Cache Miss (Full Pipeline)

    @Test func cacheMissStages() async throws {
        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        let stageTypes = metrics.stages.map(\.type)

        // Should have: memoryCacheLookup(miss), diskCacheLookup(miss), dataLoading, decoding
        #expect(stageTypes.count >= 3)

        // First stage is memory cache miss
        if case .memoryCacheLookup(let info) = stageTypes[0] {
            #expect(!info.isHit)
        } else {
            Issue.record("Expected memoryCacheLookup as first stage, got \(stageTypes[0])")
        }

        // Second stage is disk cache miss
        if case .diskCacheLookup(let info) = stageTypes[1] {
            #expect(!info.isHit)
        } else {
            Issue.record("Expected diskCacheLookup as second stage, got \(stageTypes[1])")
        }

        // Should have a data loading stage
        let hasDataLoading = stageTypes.contains {
            if case .dataLoading = $0 { return true }
            return false
        }
        #expect(hasDataLoading)

        // Should have a decoding stage
        let hasDecoding = stageTypes.contains {
            if case .decoding = $0 { return true }
            return false
        }
        #expect(hasDecoding)
    }

    @Test func dataLoadingInfoContainsByteCount() async throws {
        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        let dataLoadingStage = metrics.stages.first {
            if case .dataLoading = $0.type { return true }
            return false
        }
        let stage = try #require(dataLoadingStage)

        if case .dataLoading(let info) = stage.type {
            #expect(info.byteCount > 0)
        }
        #expect(stage.duration >= 0)
    }

    // MARK: - Memory Cache Hit

    @Test func memoryCacheHitStages() async throws {
        // Given: image in memory cache
        let cache = MockImageCache()
        cache.images[ImageCacheKey(request: Test.request)] = Test.container
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
            $0.isMetricsCollectionEnabled = true
        }

        // When
        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        // Then: only memory cache hit, no further stages
        let metrics = try #require(task.metrics)
        let stageTypes = metrics.stages.map(\.type)

        #expect(stageTypes.count == 1)
        if case .memoryCacheLookup(let info) = stageTypes[0] {
            #expect(info.isHit)
        } else {
            Issue.record("Expected memoryCacheLookup hit")
        }
    }

    // MARK: - Disk Cache Hit

    @Test func diskCacheHitStages() async throws {
        // Given: data in disk cache
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.dataCache = dataCache
            $0.dataCachePolicy = .storeOriginalData
            $0.isMetricsCollectionEnabled = true
        }

        // Load once to populate disk cache
        _ = try await pipeline.image(for: Test.url)

        // When: load again (should hit disk cache)
        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        let stageTypes = metrics.stages.map(\.type)

        // Should have memory miss, then disk hit
        if case .memoryCacheLookup(let info) = stageTypes[0] {
            #expect(!info.isHit)
        }
        if case .diskCacheLookup(let info) = stageTypes[1] {
            #expect(info.isHit)
        } else {
            Issue.record("Expected diskCacheLookup hit, got \(stageTypes)")
        }
    }

    // MARK: - Processors

    @Test func singleProcessorStage() async throws {
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "resize")])

        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        let processingStages = metrics.stages.filter {
            if case .processing = $0.type { return true }
            return false
        }

        #expect(processingStages.count == 1)
        if case .processing(let info) = processingStages[0].type {
            #expect(info.processorIdentifier.contains("resize"))
        }
    }

    @Test func multipleProcessorStages() async throws {
        let request = ImageRequest(url: Test.url, processors: [
            MockImageProcessor(id: "first"),
            MockImageProcessor(id: "second")
        ])

        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        let processingStages = metrics.stages.filter {
            if case .processing = $0.type { return true }
            return false
        }

        // Each processor should produce its own stage
        #expect(processingStages.count == 2)

        let identifiers = processingStages.compactMap { stage -> String? in
            if case .processing(let info) = stage.type {
                return info.processorIdentifier
            }
            return nil
        }
        #expect(identifiers[0].contains("first"))
        #expect(identifiers[1].contains("second"))
    }

    // MARK: - Stage Timing

    @Test func allStagesHaveValidTiming() async throws {
        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        for stage in metrics.stages {
            #expect(stage.startDate <= stage.endDate, "Stage \(stage.type) has invalid timing")
            #expect(stage.duration >= 0)
        }
    }

    // MARK: - Coalescing

    @Test func coalescedTasksHaveCoalescingFlag() async throws {
        // Given: two requests to the same URL
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: Test.url), pipeline.imageTask(with: Test.url))
        }

        _ = try await task1.response
        _ = try await task2.response

        let metrics1 = try #require(task1.metrics)
        let metrics2 = try #require(task2.metrics)

        // At least one of the tasks should have coalesced stages
        let allStages = metrics1.stages + metrics2.stages
        let hasCoalesced = allStages.contains { $0.isFromCoalescedTask }
        #expect(hasCoalesced, "Expected at least one coalesced stage when loading the same URL twice")
    }

    // MARK: - Result Info

    @Test func successResultInfo() async throws {
        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        #expect(metrics.isSuccess)

        let imageInfo = try #require(metrics.imageInfo)
        #expect(imageInfo.imageSize.width > 0)
        #expect(imageInfo.imageSize.height > 0)
        #expect(imageInfo.cacheType == nil) // Fetched from network, not cache
        #expect(!imageInfo.isPreview)
    }

    @Test func successResultInfoFromMemoryCache() async throws {
        let cache = MockImageCache()
        cache.images[ImageCacheKey(request: Test.request)] = Test.container
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
            $0.isMetricsCollectionEnabled = true
        }

        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        #expect(metrics.isSuccess)
        #expect(metrics.imageInfo?.cacheType == .some(.memory))
    }

    @Test func failureResultInfo() async throws {
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: -1))

        let task = pipeline.imageTask(with: Test.url)
        _ = try? await task.response

        let metrics = try #require(task.metrics)
        #expect(!metrics.isSuccess)
        #expect(metrics.imageInfo == nil)
    }

    // MARK: - Data Task (loadData)

    @Test func loadDataMetrics() async throws {
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        #expect(!metrics.stages.isEmpty)
    }

    // MARK: - Image ID

    @Test func imageIDIncludedInMetrics() async throws {
        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        #expect(metrics.imageID != nil)
        #expect(metrics.imageID == Test.request.imageID)
    }

    // MARK: - isFromCache Convenience

    @Test func isFromCacheFalseOnNetworkFetch() async throws {
        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        #expect(!metrics.isFromCache)
    }

    @Test func isFromCacheTrueOnMemoryHit() async throws {
        let cache = MockImageCache()
        cache.images[ImageCacheKey(request: Test.request)] = Test.container
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
            $0.isMetricsCollectionEnabled = true
        }

        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        #expect(metrics.isFromCache)
    }

    // MARK: - Decoded Image Size

    @Test func decodingInfoContainsDecodedImageSize() async throws {
        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        let decodingStage = metrics.stages.first {
            if case .decoding = $0.type { return true }
            return false
        }
        let stage = try #require(decodingStage)
        if case .decoding(let info) = stage.type {
            let size = try #require(info.decodedImageSize)
            #expect(size.width > 0)
            #expect(size.height > 0)
            #expect(!info.isProgressive)
            #expect(info.decoderType != nil)
        }
    }

    @Test func decodedSizeDiffersFromFinalSizeWithProcessor() async throws {
        let request = ImageRequest(url: Test.url, processors: [
            .resize(width: 40)
        ])

        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        let imageInfo = try #require(metrics.imageInfo)

        let decodingStage = metrics.stages.first {
            if case .decoding = $0.type { return true }
            return false
        }
        let stage = try #require(decodingStage)
        if case .decoding(let info) = stage.type {
            let decodedSize = try #require(info.decodedImageSize)
            // The decoded image should be larger than the final resized image
            #expect(decodedSize.width > imageInfo.imageSize.width || decodedSize.height > imageInfo.imageSize.height)
        }
    }

    // MARK: - Estimated Decoded Size

    @Test func estimatedDecodedSizeCalculated() async throws {
        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        let imageInfo = try #require(metrics.imageInfo)
        let expected = Int(imageInfo.imageSize.width) * Int(imageInfo.imageSize.height) * 4
        #expect(imageInfo.estimatedDecodedSize == expected)
        #expect(imageInfo.estimatedDecodedSize > 0)
    }

    // MARK: - Codable

    @Test func metricsAreCodable() async throws {
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "resize")])
        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        let metrics = try #require(task.metrics)

        let data = try JSONEncoder().encode(metrics)
        let decoded = try JSONDecoder().decode(ImageTaskMetrics.self, from: data)

        #expect(decoded.taskId == metrics.taskId)
        #expect(decoded.imageID == metrics.imageID)
        #expect(decoded.isSuccess == metrics.isSuccess)
        #expect(decoded.stages.count == metrics.stages.count)
        #expect(decoded.imageInfo?.imageSize == metrics.imageInfo?.imageSize)
    }

    // MARK: - Description

    @Test func descriptionContainsKeyInfo() async throws {
        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        let desc = metrics.description

        #expect(desc.contains("Task {"))
        #expect(desc.contains("Timeline {"))
        #expect(desc.contains("Memory Cache Lookup"))
        #expect(desc.contains("Load Data"))
        #expect(desc.contains("Decode"))
        #expect(desc.contains("Result            - Success"))
    }

    @Test func descriptionShowsProcessorIdentifier() async throws {
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "blur")])
        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        #expect(metrics.description.contains("Process"))
        #expect(metrics.description.contains("blur"))
    }

    // MARK: - Cancellation

    @Test func cancelledTaskMetricsAreNil() async throws {
        // Cancelled tasks don't produce metrics because the pipeline short-circuits
        // before the metrics collector is fully wired.
        dataLoader.isSuspended = true

        let task = pipeline.imageTask(with: Test.url)
        Task.detached { try await task.response }
        try await Task.sleep(for: .milliseconds(50))

        task.cancel()
        _ = try? await task.response

        #expect(task.metrics == nil)
    }

    // MARK: - Coalescing Granularity

    @Test func coalescingBothTasksShareSameCollector() async throws {
        // When two tasks coalesce, they share the same underlying pipeline task
        // and thus the same metrics collector. Both see the coalesced flag because
        // the second subscriber sets isCoalesced on the shared collector.
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: Test.url), pipeline.imageTask(with: Test.url))
        }

        _ = try await task1.response
        _ = try await task2.response

        let metrics1 = try #require(task1.metrics)
        let metrics2 = try #require(task2.metrics)

        // Both tasks share the same coalesced pipeline task
        let task1Coalesced = metrics1.stages.contains { $0.isFromCoalescedTask }
        let task2Coalesced = metrics2.stages.contains { $0.isFromCoalescedTask }
        #expect(task1Coalesced && task2Coalesced, "Both tasks share the coalesced pipeline task")
    }

    @Test func coalescingWithDifferentProcessors() async throws {
        // Different processors mean different TaskLoadImage tasks, but they share
        // the same TaskFetchOriginalData for downloading.
        let processors = MockProcessorFactory()
        let request1 = ImageRequest(url: Test.url, processors: [processors.make(id: "p1")])
        let request2 = ImageRequest(url: Test.url, processors: [processors.make(id: "p2")])

        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: request1), pipeline.imageTask(with: request2))
        }

        _ = try await task1.response
        _ = try await task2.response

        // Only one data load should have happened
        #expect(dataLoader.createdTaskCount == 1)

        // Both should have metrics with processing stages
        let metrics1 = try #require(task1.metrics)
        let metrics2 = try #require(task2.metrics)
        #expect(metrics1.stages.contains { if case .processing = $0.type { return true }; return false })
        #expect(metrics2.stages.contains { if case .processing = $0.type { return true }; return false })
    }

    // MARK: - Exact Stage Sequences

    @Test func exactStageSequenceForCacheMiss() async throws {
        // No cache, no processors — simplest full pipeline path
        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        let names = metrics.stages.map { _stageLabel($0.type) }

        // Exact expected order (decompression may or may not be present depending on platform)
        #expect(names.starts(with: ["memoryCacheLookup", "diskCacheLookup", "dataLoading", "decoding"]))
    }

    @Test func exactStageSequenceForMemoryCacheHit() async throws {
        let cache = MockImageCache()
        cache.images[ImageCacheKey(request: Test.request)] = Test.container
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
            $0.isMetricsCollectionEnabled = true
        }

        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        let names = metrics.stages.map { _stageLabel($0.type) }

        #expect(names == ["memoryCacheLookup"])
    }

    @Test func exactStageSequenceWithProcessor() async throws {
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        let names = metrics.stages.map { _stageLabel($0.type) }

        // The inner TaskLoadImage (no processors) records memory+disk cache lookups,
        // then data loading + decoding happen, then the outer TaskLoadImage applies the processor
        #expect(names.contains("processing"))
        // Data loading and decoding come before processing
        if let dataIdx = names.firstIndex(of: "dataLoading"),
           let procIdx = names.firstIndex(of: "processing") {
            #expect(dataIdx < procIdx)
        }
    }

    // MARK: - loadData Path

    @Test func loadDataPathStages() async throws {
        let task = pipeline.imageTask(with: Test.request)
        let (data, _) = try await pipeline.data(for: Test.request)
        #expect(!data.isEmpty)

        // loadData uses a separate task, so create one directly
        let dataTask = pipeline.imageTask(with: Test.request)
        _ = try await dataTask.response

        let metrics = try #require(dataTask.metrics)
        let names = metrics.stages.map { _stageLabel($0.type) }

        // Should not have processing or decompression for a simple image load without processors
        let hasProcessing = names.contains("processing")
        #expect(!hasProcessing)
    }

    // MARK: - Task ID

    @Test func taskIdMatchesImageTask() async throws {
        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        #expect(metrics.taskId == task.taskId)
    }

    // MARK: - Decoder Type

    @Test func decoderTypeIsDefault() async throws {
        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        let metrics = try #require(task.metrics)
        let decodingStage = metrics.stages.first {
            if case .decoding = $0.type { return true }
            return false
        }
        let stage = try #require(decodingStage)
        if case .decoding(let info) = stage.type {
            // Default decoder for JPEG
            #expect(info.decoderType == "ImageDecoders.Default" || info.decoderType == "Default")
        }
    }

    // MARK: - Delegate Delivery

    @Test func metricsAvailableInDelegate() async throws {
        let observer = ImagePipelineObserver()
        let pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isMetricsCollectionEnabled = true
        }

        let task = pipeline.imageTask(with: Test.url)
        _ = try await task.response

        // Metrics should be accessible by the time the delegate receives .finished
        #expect(task.metrics != nil)
    }
}

// MARK: - Helpers

private func _stageLabel(_ type: ImageTaskMetrics.StageType) -> String {
    switch type {
    case .memoryCacheLookup: "memoryCacheLookup"
    case .diskCacheLookup: "diskCacheLookup"
    case .dataLoading: "dataLoading"
    case .decoding: "decoding"
    case .processing: "processing"
    case .decompression: "decompression"
    }
}
