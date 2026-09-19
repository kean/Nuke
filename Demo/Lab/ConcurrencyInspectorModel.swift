// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import os
import QuartzCore

/// Starts a burst of requests on a pipeline of its own and reads, when asked,
/// where each task is and what the five task queues run.
///
/// The pipeline has no memory cache and a disk cache that keeps nothing, so
/// that it still encodes what its policy would store. Every request has a URL
/// of its own, so no two tasks share work.
@MainActor @Observable
final class ConcurrencyInspectorModel {
    /// Where each task of the last burst is, oldest first.
    private(set) var stages: [InspectorStage] = []
    private(set) var queues: [QueueStatus] = []
    private(set) var isRunning = false
    /// How long the last burst has run, or took.
    private(set) var elapsed: TimeInterval = 0

    static let burstCount = 240

    struct QueueStatus: Identifiable, Equatable {
        let title: String
        let queue: KeyPath<ImagePipeline.Configuration, TaskQueue>
        let running: Int
        let limit: Int
        let isSuspended: Bool

        var id: String { title }
    }

    @ObservationIgnored private let recorder = InspectorRecorder()
    /// Made on first use rather than in `init`, which SwiftUI runs each time it
    /// makes the view.
    @ObservationIgnored private lazy var pipeline = makePipeline()
    @ObservationIgnored private var tasks: [ImageTask] = []
    @ObservationIgnored private var starting: Task<Void, Never>?
    @ObservationIgnored private var startedAt: CFTimeInterval = 0
    /// Where the last burst starts in the record.
    @ObservationIgnored private var firstIndex = 0

    /// The queues, and where the probe counts the work running on each. It
    /// can't see processing, which the screen's processor counts.
    private static let queuePaths: [(String, KeyPath<ImagePipeline.Configuration, TaskQueue>, KeyPath<DemoPipelineDiagnostics, DemoPipelineDiagnostics.Queue>?)] = [
        ("Data Loading", \.dataLoadingQueue, \.dataLoadingQueue),
        ("Decoding", \.imageDecodingQueue, \.decodingQueue),
        ("Processing", \.imageProcessingQueue, nil),
        ("Decompressing", \.imageDecompressingQueue, \.decompressingQueue),
        ("Encoding", \.imageEncodingQueue, \.encodingQueue)
    ]

    private func makePipeline() -> ImagePipeline {
        // 60 ms before the first byte, then six chunks 40 ms apart: 0.3 s a
        // download, whatever its size.
        let pace = DemoFixtureLoader.Pace(latency: .milliseconds(60), chunkCount: 6, interval: .milliseconds(40))
        var configuration = ImagePipeline.Configuration(dataLoader: DemoFixtureLoader(pace: pace))
        configuration.imageCache = nil
        configuration.dataCache = DiscardingDataCache()
        configuration.dataCachePolicy = .automatic
        // The probe counts decodes only on a pipeline that doesn't record them.
        configuration.isDiagnosticsEnabled = false
        let recorder = recorder
        return DemoPipelineProbe.makePipeline(
            "Concurrency Inspector",
            configuration: configuration,
            delegate: InspectorDelegate(recorder: recorder),
            onLoad: { event in
                switch event.kind {
                case .started: recorder.advance(event.request, to: .loading)
                case .completed(.none): recorder.dataLoaded(event.request)
                default: break
                }
            }
        )
    }

    // MARK: Burst

    func start() {
        guard !isRunning else { return }
        isRunning = true
        elapsed = 0
        starting = Task {
            // Made up front, so that no download waits for its fixture.
            for fixture in [DemoFixture.largeJPEG] + DemoFixture.photos {
                _ = try? await DemoFixtureStore.shared.entry(for: fixture)
            }
            guard !Task.isCancelled else { return }
            firstIndex = recorder.add(Self.burstCount)
            startedAt = CACurrentMediaTime()
            tasks = (firstIndex..<firstIndex + Self.burstCount).map {
                pipeline.imageTask(with: makeRequest($0))
            }
        }
    }

    /// Photos, photos resized and blurred, and thumbnails of the 12 MP JPEG.
    private func makeRequest(_ index: Int) -> ImageRequest {
        let fixture: DemoFixture = index % 4 == 3 ? .largeJPEG : .photo(index % DemoFixture.photos.count)
        let url = fixture.url.appending(queryItems: [URLQueryItem(name: "n", value: String(index))])
        let isProcessed = index % 4 == 1
        var request = ImageRequest(url: url, processors: isProcessed ? [InspectedProcessor(recorder: recorder)] : [])
        if fixture == .largeJPEG {
            request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 480)
        }
        request.userInfo[InspectorTag.key] = InspectorTag(index: index, isProcessed: isProcessed)
        return request
    }

    func cancelAll() {
        for task in tasks {
            task.cancel()
        }
    }

    func toggleSuspended(_ status: QueueStatus) {
        pipeline.configuration[keyPath: status.queue].isSuspended.toggle()
        sample()
    }

    /// Cancels the burst and resumes the queues, so that nothing the pipeline
    /// holds waits on a queue that nobody can resume.
    func leave() {
        starting?.cancel()
        cancelAll()
        for (_, queue, _) in Self.queuePaths {
            pipeline.configuration[keyPath: queue].isSuspended = false
        }
    }

    // MARK: Sampling

    func sample() {
        let stages = recorder.stages(from: firstIndex)
        if stages != self.stages {
            self.stages = stages
        }
        let diagnostics = DemoPipelineProbe.diagnostics(for: pipeline)
        let queues = Self.queuePaths.map { title, path, figures in
            let queue = pipeline.configuration[keyPath: path]
            let running = figures.map { diagnostics?[keyPath: $0].inFlightCount ?? 0 } ?? recorder.processingCount
            return QueueStatus(title: title, queue: path, running: running, limit: queue.maxConcurrentTaskCount, isSuspended: queue.isSuspended)
        }
        if queues != self.queues {
            self.queues = queues
        }
        guard isRunning, !tasks.isEmpty else { return }
        elapsed = CACurrentMediaTime() - startedAt
        if stages.allSatisfy(\.isFinished) {
            isRunning = false
            tasks = []
        }
    }
}

/// Where a task is. A stage includes the wait for its queue.
enum InspectorStage: Int, CaseIterable, Comparable {
    /// Until its download starts: waiting for a data loading slot or the
    /// rate limiter.
    case waiting
    case loading
    case decoding
    case processing
    case decompressing
    case image
    case cancelled
    case failed

    var title: String {
        String(describing: self)
    }

    var isFinished: Bool {
        self >= .image
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Carried in a request's `userInfo`, which the pipeline keeps on the
/// requests of the work it does for it.
private struct InspectorTag: Sendable {
    static let key: ImageRequest.UserInfoKey = "com.github.kean.NukeDemo.ConcurrencyInspector"

    let index: Int
    let isProcessed: Bool
}

extension ImageRequest {
    fileprivate var inspectorTag: InspectorTag? {
        userInfo[InspectorTag.key] as? InspectorTag
    }
}

/// Where each task is, by the index its request carries, written from the
/// pipeline's threads.
private final class InspectorRecorder: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var stages: [InspectorStage] = []
        var processingCount = 0
    }

    /// Adds `count` waiting tasks, and returns the index of the first.
    func add(_ count: Int) -> Int {
        state.withLock { state in
            defer { state.stages += repeatElement(.waiting, count: count) }
            return state.stages.count
        }
    }

    /// Moves a task on, and never back.
    func advance(_ request: ImageRequest, to stage: InspectorStage) {
        guard let tag = request.inspectorTag else { return }
        state.withLock { state in
            state.stages[tag.index] = max(state.stages[tag.index], stage)
        }
    }

    /// The data is in: a thumbnail waits for the decoding queue, a photo is
    /// decoded at once, and a processed one then waits for processing.
    func dataLoaded(_ request: ImageRequest) {
        advance(request, to: request.inspectorTag?.isProcessed == true ? .processing : .decoding)
    }

    func stages(from index: Int) -> [InspectorStage] {
        state.withLock { Array($0.stages[index...]) }
    }

    var processingCount: Int {
        state.withLock { $0.processingCount }
    }

    func processing<T>(_ body: () -> T) -> T {
        state.withLock { $0.processingCount += 1 }
        defer { state.withLock { $0.processingCount -= 1 } }
        return body()
    }
}

/// Hears the pipeline queue a decompression and a task finish, and otherwise
/// does what Nuke's own delegate does.
private final class InspectorDelegate: ImagePipeline.Delegate {
    private let recorder: InspectorRecorder
    private let defaults = DemoDefaultDelegate()

    init(recorder: InspectorRecorder) {
        self.recorder = recorder
    }

    /// Asked right before the pipeline queues a decompression, and only then.
    func shouldDecompress(response: ImageResponse, for request: ImageRequest, pipeline: ImagePipeline) -> Bool {
        let shouldDecompress = defaults.shouldDecompress(response: response, for: request, pipeline: pipeline)
        if shouldDecompress {
            recorder.advance(request, to: .decompressing)
        }
        return shouldDecompress
    }

    @ImagePipelineActor
    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        guard case .finished(let result) = event else { return }
        let stage: InspectorStage = switch result {
        case .success: .image
        case .failure(.cancelled): .cancelled
        case .failure: .failed
        }
        recorder.advance(task.request, to: stage)
    }
}

/// A resize and a blur that counts the work running, which the probe can't
/// see: processors come with the request.
private struct InspectedProcessor: ImageProcessing {
    let recorder: InspectorRecorder
    private let base = ImageProcessors.Composition([
        ImageProcessors.Resize(width: 80),
        ImageProcessors.GaussianBlur(radius: 8)
    ])

    var identifier: String {
        "com.github.kean.NukeDemo.ConcurrencyInspector.blur"
    }

    func process(_ image: PlatformImage) -> PlatformImage? {
        recorder.processing { base.process(image) }
    }
}

/// A disk cache that keeps nothing: the pipeline still encodes what its
/// policy stores, and writes no file.
private struct DiscardingDataCache: DataCaching {
    func cachedData(for key: String) -> Data? { nil }
    func containsData(for key: String) -> Bool { false }
    func storeData(_ data: Data, for key: String) {}
    func removeData(for key: String) {}
    func removeAll() {}
}
