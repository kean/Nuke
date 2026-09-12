// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import OSLog

// A probe on every pipeline the demo builds, with nothing in Nuke changed.
//
// `DemoPipelineProbe` is the pipeline's delegate. It forwards every call to the
// delegate the screen passed in, or to the defaults, and counts on the way. The
// pipeline does what it did without the probe: every argument and result is
// passed on unchanged, and `willLoadData`, which holds a data loading slot
// while it runs, gains no suspension.
//
// What the probe can't see:
// - Work waiting in a queue. `TaskQueue` keeps its counts to itself, so a
//   queue reports its public limit, and the work running only where the probe
//   sees it start and end.
// - Processing. Processors come with the request, not from the delegate, and
//   wrapping them would change the requests.
// - `data(for:)` and prefetching into the disk cache. They run data tasks, which
//   no task hook hears of.
// - Memory cache hits without a task. NukeUI's views look the image up before
//   they start a task, and a hit never becomes one.
// - The rate limiter. A download it holds back is counted once it starts.

/// The delegate of every pipeline the demo builds: it counts what the pipeline
/// does, forwards every call to the delegate it wraps, and logs the record of
/// every finished task when diagnostics are on.
///
/// Create pipelines with ``makePipeline(_:configuration:delegate:)``, then
/// sample the figures on a timer: ``total`` for every pipeline,
/// ``pipelines`` for each one alive, and ``diagnostics(for:)`` for one of them.
///
/// A screen that needs a delegate of its own passes it in: the probe forwards
/// every call to it and counts what it returns.
final class DemoPipelineProbe: ImagePipeline.Delegate {
    /// The name the pipeline is listed under.
    let label: String
    let configuration: ImagePipeline.Configuration

    private let counters: Counters
    private let base: any ImagePipeline.Delegate

    private init(label: String, configuration: ImagePipeline.Configuration, delegate: (any ImagePipeline.Delegate)?) {
        self.label = label
        self.configuration = configuration
        self.counters = Counters(label: label)
        self.base = delegate ?? DefaultDelegate()
    }

    // MARK: Creating Pipelines

    /// Creates a pipeline with a probe as its delegate.
    ///
    /// - parameters:
    ///   - label: The name the pipeline is listed under.
    ///   - delegate: A delegate of the screen's own. The probe forwards every
    ///   call to it.
    static func makePipeline(
        _ label: String,
        configuration: ImagePipeline.Configuration = .withURLCache,
        delegate: (any ImagePipeline.Delegate)? = nil
    ) -> ImagePipeline {
        let probe = DemoPipelineProbe(label: label, configuration: configuration, delegate: delegate)
        let pipeline = ImagePipeline(configuration: configuration, delegate: probe)
        registry.withLock {
            $0.entries.append(Registry.Entry(counters: probe.counters, probe: probe, pipeline: pipeline))
        }
        return pipeline
    }

    /// Creates a pipeline with a probe as its delegate, the way
    /// `ImagePipeline(delegate:_:)` does.
    static func makePipeline(
        _ label: String,
        delegate: (any ImagePipeline.Delegate)? = nil,
        _ configure: (inout ImagePipeline.Configuration) -> Void
    ) -> ImagePipeline {
        var configuration = ImagePipeline.Configuration()
        configure(&configuration)
        return makePipeline(label, configuration: configuration, delegate: delegate)
    }

    // MARK: Sampling

    /// This pipeline's figures.
    var diagnostics: DemoPipelineDiagnostics {
        var diagnostics = counters.figures
        diagnostics.dataLoadingQueue.set(configuration.dataLoadingQueue)
        diagnostics.decodingQueue.set(configuration.imageDecodingQueue)
        diagnostics.processingQueue.set(configuration.imageProcessingQueue)
        diagnostics.decompressingQueue.set(configuration.imageDecompressingQueue)
        diagnostics.encodingQueue.set(configuration.imageEncodingQueue)
        return diagnostics
    }

    /// The figures of the probe of `pipeline`, or `nil` if the probe didn't
    /// create it.
    static func diagnostics(for pipeline: ImagePipeline) -> DemoPipelineDiagnostics? {
        probe(for: pipeline)?.diagnostics
    }

    /// The probe of `pipeline`, or `nil` if the probe didn't create it.
    static func probe(for pipeline: ImagePipeline) -> DemoPipelineProbe? {
        registry.withLock { registry in
            registry.entries.first { $0.pipeline === pipeline }?.probe
        }
    }

    /// The figures of every pipeline alive, oldest first.
    static var pipelines: [DemoPipelineDiagnostics] {
        liveProbes.map(\.diagnostics)
    }

    /// Every pipeline the demo has built, added up since the last reset,
    /// including the pipelines that are gone.
    ///
    /// The figures are counted per pipeline and added up here, rather than
    /// counted into one aggregate, because the pipelines don't do comparable
    /// work. The shared one serves every catalog screen for as long as the app
    /// runs; Caching, Progressive Decoding, and Scroll Stress build their own
    /// and drop them when they close. Kept apart, a screen measuring its own
    /// pipeline reads ``diagnostics(for:)`` without whatever the shared
    /// pipeline was doing meanwhile, and the pipelines never wait on each
    /// other's lock. A pipeline that goes away leaves its counts in the total,
    /// so the total never goes backwards.
    static var total: DemoPipelineDiagnostics {
        // First: it moves the figures of the pipelines that are gone into
        // the retired ones.
        let probes = liveProbes
        var total = registry.withLock { $0.retired }
        total.label = "All pipelines"
        // A queue that no pipeline counts stays `nil`.
        total.dataLoadingQueue = .init(inFlightCount: nil)
        total.decodingQueue = .init(inFlightCount: nil)
        total.processingQueue = .init(inFlightCount: nil)
        total.decompressingQueue = .init(inFlightCount: nil)
        total.encodingQueue = .init(inFlightCount: nil)
        var queues = Set<ObjectIdentifier>()
        for probe in probes {
            let diagnostics = probe.diagnostics
            let configuration = probe.configuration
            total.add(diagnostics)
            total.dataLoadingQueue.add(diagnostics.dataLoadingQueue, isDistinctQueue: queues.insert(ObjectIdentifier(configuration.dataLoadingQueue)).inserted)
            total.decodingQueue.add(diagnostics.decodingQueue, isDistinctQueue: queues.insert(ObjectIdentifier(configuration.imageDecodingQueue)).inserted)
            total.processingQueue.add(diagnostics.processingQueue, isDistinctQueue: queues.insert(ObjectIdentifier(configuration.imageProcessingQueue)).inserted)
            total.decompressingQueue.add(diagnostics.decompressingQueue, isDistinctQueue: queues.insert(ObjectIdentifier(configuration.imageDecompressingQueue)).inserted)
            total.encodingQueue.add(diagnostics.encodingQueue, isDistinctQueue: queues.insert(ObjectIdentifier(configuration.imageEncodingQueue)).inserted)
        }
        return total
    }

    /// Starts every pipeline's figures over, and forgets the pipelines that
    /// are gone. Work running now stays counted as running.
    static func reset() {
        let counters = registry.withLock { registry in
            registry.retired = DemoPipelineDiagnostics()
            return registry.entries.map(\.counters)
        }
        for counters in counters {
            counters.reset()
        }
    }

    /// The probes of the pipelines alive, oldest first. The figures of the
    /// pipelines that are gone move into the retired total on the way.
    static var liveProbes: [DemoPipelineProbe] {
        let (probes, retired) = registry.withLock { registry in
            var probes: [DemoPipelineProbe] = []
            var retired: [Counters] = []
            registry.entries.removeAll { entry in
                if let probe = entry.probe {
                    probes.append(probe)
                    return false
                }
                retired.append(entry.counters)
                return true
            }
            return (probes, retired)
        }
        if !retired.isEmpty {
            let figures = retired.map(\.figures.retired)
            registry.withLock { registry in
                for figures in figures {
                    registry.retired.add(figures)
                }
            }
        }
        return probes
    }

    private static let registry = OSAllocatedUnfairLock(initialState: Registry())

    private struct Registry: Sendable {
        struct Entry: Sendable {
            /// Held strongly, so the counts of a pipeline that is gone are
            /// still there to move into ``retired``.
            let counters: Counters
            weak var probe: DemoPipelineProbe?
            weak var pipeline: ImagePipeline?
        }

        var entries: [Entry] = []
        /// The counts of the pipelines that are gone.
        var retired = DemoPipelineDiagnostics()
    }

    // MARK: ImagePipeline.Delegate

    func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> (any ImageDecoding)? {
        base.imageDecoder(for: context, pipeline: pipeline)
    }

    func imageEncoder(for context: ImageEncodingContext, pipeline: ImagePipeline) -> any ImageEncoding {
        base.imageEncoder(for: context, pipeline: pipeline)
    }

    func previewPolicy(for context: ImageDecodingContext, pipeline: ImagePipeline) -> ImagePipeline.PreviewPolicy {
        base.previewPolicy(for: context, pipeline: pipeline)
    }

    func dataLoader(for request: ImageRequest, pipeline: ImagePipeline) -> any DataLoading {
        counters.downloadRequested()
        return base.dataLoader(for: request, pipeline: pipeline)
    }

    @ImagePipelineActor
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        try await base.willLoadData(for: request, urlRequest: urlRequest, pipeline: pipeline)
    }

    func imageCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any ImageCaching)? {
        base.imageCache(for: request, pipeline: pipeline)
    }

    func dataCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any DataCaching)? {
        base.dataCache(for: request, pipeline: pipeline)
    }

    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        base.cacheKey(for: request, pipeline: pipeline)
    }

    @ImagePipelineActor
    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline) async -> Data? {
        let data = await base.willCache(data: data, image: image, for: request, pipeline: pipeline)
        if let data, !data.isEmpty {
            counters.diskWrite(byteCount: data.count, isEncodedImage: image != nil)
        }
        return data
    }

    func shouldDecompress(response: ImageResponse, for request: ImageRequest, pipeline: ImagePipeline) -> Bool {
        let shouldDecompress = base.shouldDecompress(response: response, for: request, pipeline: pipeline)
        if !shouldDecompress {
            counters.decompressionDeclined()
        }
        return shouldDecompress
    }

    func decompress(response: ImageResponse, request: ImageRequest, pipeline: ImagePipeline) -> ImageResponse {
        counters.decompressionStarted()
        let startedAt = ContinuousClock.now
        defer { counters.decompressionFinished(startedAt: startedAt) }
        return base.decompress(response: response, request: request, pipeline: pipeline)
    }

    func imageTaskCreated(_ task: ImageTask, pipeline: ImagePipeline) {
        counters.taskCreated(task)
        base.imageTaskCreated(task, pipeline: pipeline)
    }

    @ImagePipelineActor
    func imageTaskDidStart(_ task: ImageTask, pipeline: ImagePipeline) {
        base.imageTaskDidStart(task, pipeline: pipeline)
    }

    @ImagePipelineActor
    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        if case .finished(let result) = event {
            counters.taskFinished(task, with: result)
            if let metrics = task.metrics {
                Self.log(metrics)
            }
        }
        base.imageTask(task, didReceiveEvent: event, pipeline: pipeline)
    }

    // MARK: Logging

    private static let logger = Logger(subsystem: "com.github.kean.NukeDemo", category: "ImageTask")

    /// Logs where the time of a finished task went.
    ///
    /// The pipeline records it only when the app is launched with the
    /// `NUKE_DIAGNOSTICS_ENABLED` environment variable set – the switch lives
    /// in Nuke, see ``ImagePipeline/Configuration-swift.struct/isDiagnosticsEnabled``.
    /// The variable is in the NukeDemo scheme, unticked: Edit Scheme › Run ›
    /// Arguments › Environment Variables. Every task then finishes with a
    /// timeline in Console, under the `com.github.kean.NukeDemo` subsystem:
    ///
    /// ```
    /// xcrun simctl spawn booted log stream --predicate 'subsystem == "com.github.kean.NukeDemo"'
    /// ```
    private static func log(_ metrics: ImageTask.Metrics) {
        let level: OSLogType = switch metrics.outcome {
        case .failure: .error
        case .cancelled: .info
        default: .default
        }
        logger.log(level: level, "\(metrics.description, privacy: .public)")
    }
}

/// The delegate a probe forwards to when the screen has none: every method is
/// the protocol's default.
private final class DefaultDelegate: ImagePipeline.Delegate {}

extension DemoPipelineDiagnostics.Queue {
    fileprivate mutating func set(_ queue: TaskQueue) {
        limit = queue.maxConcurrentTaskCount
        isSuspended = queue.isSuspended
    }
}
