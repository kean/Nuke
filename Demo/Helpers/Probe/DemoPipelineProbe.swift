// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import NukeVideo
import OSLog

// A probe on every pipeline the demo builds, with nothing in Nuke changed.
//
// `DemoPipelineProbe` is the pipeline's delegate. It forwards every call to the
// delegate the screen passed in, or to the defaults, and counts on the way.
// Where a hook returns something the pipeline works with – the data loader, the
// decoder, the encoder, the caches – it returns the same thing behind a
// decorator that counts what passes through. A `DataLoader` isn't wrapped: it
// is heard through its session delegate instead (see `SessionObserver`). The
// pipeline does what it did without the probe: the decorators pass on every
// argument, result, and callback, and `willLoadData`, which holds a data
// loading slot while it runs, gains no suspension.
//
// The things it changes are where fixtures come from, and, while the demo's
// network conditions are on, how downloads arrive. A request for a fixture
// URL, and every request while the demo is offline, goes to a
// `DemoFixtureLoader` rather than the loader the pipeline was configured with,
// unless its loader never goes to the network (`DemoLocalDataLoading`);
// while the conditions are on, whichever loader that is sits behind a
// `DemoConditionedDataLoader` (see `dataLoader(for:pipeline:)`). Routed there,
// rather than configured, a `DataLoader` stays unwrapped and observed for
// everything else.
//
// What the probe can't see:
// - Work waiting in a queue. `TaskQueue` keeps its counts to itself, so a
//   queue reports the work the decorators see running, and its public limit.
// - Processing. Processors come with the request, not from the delegate, and
//   wrapping them would change the requests.
// - `data(for:)` and prefetching into the disk cache. They run data tasks, which
//   no task hook hears of; their downloads and disk reads are still counted.
// - Memory cache hits without a task, beyond the ones on the main thread (see
//   `DemoPipelineDiagnostics.memoryHitWithoutTaskCount`).
// - The rate limiter. A download it holds back is counted once it starts.
// - The decoders of a pipeline that records diagnostics. The record names the
//   decoder's type, which a wrapper would replace, so they aren't wrapped and
//   their times come from the finished tasks' metrics, without failures or a
//   count in flight.
// - Any decoder other than the ones Nuke ships, on a pipeline that doesn't
//   record diagnostics, unless it is a `DemoSynchronousDecoding`. It isn't
//   wrapped, and its decodes aren't counted – see `isTimed(_:)`.
// - Where a custom loader's data came from: only a `DataLoader` says `URLCache`.
// - A `DataLoader` that already has a delegate. One that two pipelines share
//   is counted by the probe of the first.

/// The delegate of every pipeline the demo builds: it counts what the pipeline
/// does, forwards every call to the delegate it wraps, and logs the record of
/// every finished task when diagnostics are on.
///
/// Create pipelines with ``makePipeline(_:configuration:delegate:onEvent:)``,
/// then sample the figures on a timer: ``total`` for every pipeline,
/// ``pipelines`` for each one alive, ``diagnostics(for:)`` for one of them, and
/// ``sampleCaches(for:)``, less often, for what the caches hold.
///
/// A screen that needs a delegate of its own passes it in: the probe forwards
/// every call to it and counts what it returns. A screen that lists the calls
/// passes an event handler too (see ``Event``), and one that lists the calls
/// between the pipeline and its data loader, a load event handler (see
/// ``LoadEvent``).
final class DemoPipelineProbe: ImagePipeline.Delegate {
    /// The name the pipeline is listed under.
    let label: String
    let configuration: ImagePipeline.Configuration

    private let counters: Counters
    private let base: any ImagePipeline.Delegate
    private let imageCache: CountingImageCache?
    /// `true` for a pipeline recording diagnostics, whose decoders aren't wrapped.
    private let isRecordingDiagnostics: Bool
    private let onEvent: EventHandler?
    private let onLoad: LoadEventHandler?
    /// Answers the requests for fixtures, at the pace of the configured
    /// loader.
    private let fixtureLoader: DemoFixtureLoader

    private init(label: String, configuration: ImagePipeline.Configuration, delegate: (any ImagePipeline.Delegate)?, onEvent: EventHandler?, onLoad: LoadEventHandler?) {
        let counters = Counters(label: label)
        self.label = label
        self.configuration = configuration
        self.counters = counters
        self.base = delegate ?? DemoDefaultDelegate()
        self.onEvent = onEvent
        self.onLoad = onLoad
        self.imageCache = configuration.imageCache.map { CountingImageCache($0, counters: counters) }
        self.isRecordingDiagnostics = configuration.isDiagnosticsEnabled
        self.fixtureLoader = Self.makeFixtureLoader(for: configuration)

        // The loader reads its delegate without a lock, so it is set before
        // the pipeline exists and can start a download.
        if let dataLoader = configuration.dataLoader as? DataLoader, dataLoader.delegate == nil {
            dataLoader.delegate = SessionObserver(counters: counters)
        }
    }

    // MARK: Creating Pipelines

    /// Creates a pipeline with a probe as its delegate.
    ///
    /// - parameters:
    ///   - label: The name the pipeline is listed under.
    ///   - delegate: A delegate of the screen's own. The probe forwards every
    ///   call to it.
    ///   - onEvent: Called with the calls the pipeline makes to the delegate,
    ///   for a screen that lists them. See ``Event``.
    ///   - onLoad: Called with the calls between the pipeline and its data
    ///   loader, for a screen that lists them. See ``LoadEvent``.
    static func makePipeline(
        _ label: String,
        configuration: ImagePipeline.Configuration = .withURLCache,
        delegate: (any ImagePipeline.Delegate)? = nil,
        onEvent: EventHandler? = nil,
        onLoad: LoadEventHandler? = nil
    ) -> ImagePipeline {
        let probe = DemoPipelineProbe(label: label, configuration: configuration, delegate: delegate, onEvent: onEvent, onLoad: onLoad)
        let pipeline = ImagePipeline(configuration: configuration, delegate: probe)
        // Moves the pipelines that are gone out of the registry, which
        // sampling does too, so a screen that makes one pipeline after
        // another doesn't pile them up while nothing samples.
        _ = liveProbes
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
        if isRecordingDiagnostics {
            diagnostics.decodingQueue.inFlightCount = nil
        }
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
        registry.withLock { registry in
            var probes: [DemoPipelineProbe] = []
            var retired = DemoPipelineDiagnostics()
            registry.entries.removeAll { entry in
                // By the pipeline: a caller that holds on to a probe, like the
                // HUD across a cache sample, keeps the probe but not the
                // pipeline alive.
                if entry.pipeline != nil, let probe = entry.probe {
                    probes.append(probe)
                    return false
                }
                retired.add(entry.counters.figures.retired)
                return true
            }
            // In the same lock, so that a total never misses a pipeline on its
            // way from one list to the other.
            registry.retired.add(retired)
            return probes
        }
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
        guard let decoder = base.imageDecoder(for: context, pipeline: pipeline) else {
            return nil
        }
        // The pipeline records the type of the decoder, which a wrapper would
        // replace.
        guard !isRecordingDiagnostics, Self.isTimed(decoder) else {
            return decoder
        }
        return CountingDecoder(decoder, counters: counters)
    }

    /// Whether the probe wraps `decoder` to time it: only the decoders that
    /// ship with Nuke, which all decode in the synchronous `decode(_:)`, and
    /// the demo's own that say they do (``DemoSynchronousDecoding``).
    ///
    /// Any other decoder is passed on as it is, and its decodes aren't
    /// counted. The pipeline finds a decoder that decodes asynchronously by a
    /// cast to `AsyncImageDecoding`, which is SPI rather than public API. A
    /// wrapper would fail that cast and the pipeline would call a `decode(_:)`
    /// that throws, and the demo builds against the public API only, so it
    /// can't tell such a decoder apart before wrapping it.
    private static func isTimed(_ decoder: any ImageDecoding) -> Bool {
        decoder is ImageDecoders.Default || decoder is ImageDecoders.Video || decoder is ImageDecoders.Empty
            || decoder is any DemoSynchronousDecoding
    }

    func imageEncoder(for context: ImageEncodingContext, pipeline: ImagePipeline) -> any ImageEncoding {
        CountingEncoder(base.imageEncoder(for: context, pipeline: pipeline), counters: counters)
    }

    func previewPolicy(for context: ImageDecodingContext, pipeline: ImagePipeline) -> ImagePipeline.PreviewPolicy {
        base.previewPolicy(for: context, pipeline: pipeline)
    }

    /// The loader the delegate returns, unless the request is for a fixture,
    /// or the demo is offline and the loader would go to the network: then a
    /// ``DemoFixtureLoader``, so that nothing but a fixture loader sees a
    /// fixture URL, and nothing goes to the network offline. While
    /// ``DemoNetworkConditions`` are on, the loader is behind a
    /// ``DemoConditionedDataLoader``, a `DataLoader` included.
    ///
    /// The pipeline asks once per download, after coalescing and once a data
    /// loading slot is free, so the mode and the conditions are read for
    /// every download, and a switch applies to the next one. A delegate that
    /// returns a fixture loader of its own keeps it, with its pace, and one
    /// that returns a ``DemoLocalDataLoading`` loader keeps it offline.
    func dataLoader(for request: ImageRequest, pipeline: ImagePipeline) -> any DataLoading {
        counters.downloadRequested()
        var dataLoader = base.dataLoader(for: request, pipeline: pipeline)
        let isOfflineRequest = DemoFixtureMode.isOffline && !(dataLoader is any DemoLocalDataLoading)
        if !(dataLoader is DemoFixtureLoader), DemoFixture.isFixture(request.url) || isOfflineRequest {
            dataLoader = fixtureLoader
        }
        if let conditions = DemoNetworkConditions.current {
            return CountingDataLoader(DemoConditionedDataLoader(dataLoader, profile: conditions), counters: counters, request: request, onLoad: onLoad)
        }
        // Wrapped, a `DataLoader` would lose the `URLSession` metrics the
        // pipeline records. Its session delegate counts it instead.
        guard !(dataLoader is DataLoader) else {
            return dataLoader
        }
        return CountingDataLoader(dataLoader, counters: counters, request: request, onLoad: onLoad)
    }

    /// A fixture loader at the pace of the configured loader: a
    /// ``ThrottledDataLoader``'s chunks, so that Progressive Decoding shows
    /// its scans offline, each a little later than the pipeline's
    /// `progressiveDecodingInterval` so that none is skipped; the one a
    /// ``PacedDataLoader`` keeps for this, at its pace; everything at once for
    /// any other.
    private static func makeFixtureLoader(for configuration: ImagePipeline.Configuration) -> DemoFixtureLoader {
        switch configuration.dataLoader {
        case let loader as DemoFixtureLoader:
            return loader
        case let loader as PacedDataLoader:
            return loader.fixtureLoader
        case let loader as ThrottledDataLoader:
            var pace = DemoFixtureLoader.Pace.throttled(chunkSize: loader.chunkSize, interval: loader.interval)
            if configuration.isProgressiveDecodingEnabled {
                pace.scanInterval = .seconds(configuration.progressiveDecodingInterval) + .milliseconds(100)
            }
            return DemoFixtureLoader(pace: pace)
        default:
            return DemoFixtureLoader()
        }
    }

    @ImagePipelineActor
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        let urlRequest = try await base.willLoadData(for: request, urlRequest: urlRequest, pipeline: pipeline)
        onEvent?(Event(request: request, kind: .willLoadData(urlRequest)))
        // A mark the server never sees, for the session observer.
        return request.options.contains(.skipDataLoadingQueue) ? UnqueuedRequest.tag(urlRequest) : urlRequest
    }

    func imageCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any ImageCaching)? {
        guard let cache = base.imageCache(for: request, pipeline: pipeline) else {
            return nil
        }
        if let imageCache, imageCache.base === cache {
            return imageCache
        }
        return CountingImageCache(cache, counters: counters)
    }

    func dataCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any DataCaching)? {
        base.dataCache(for: request, pipeline: pipeline).map {
            CountingDataCache(base: $0, counters: counters)
        }
    }

    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        let key = base.cacheKey(for: request, pipeline: pipeline)
        onEvent?(Event(request: request, kind: .cacheKey(key)))
        return key
    }

    @ImagePipelineActor
    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline) async -> Data? {
        let stored = await base.willCache(data: data, image: image, for: request, pipeline: pipeline)
        // The pipeline stores nothing for empty data, the same as for `nil`.
        let storedByteCount = stored.flatMap { $0.isEmpty ? nil : $0.count }
        if let storedByteCount {
            counters.diskWrite(byteCount: storedByteCount, isEncodedImage: image != nil)
        }
        onEvent?(Event(request: request, kind: .willCache(byteCount: data.count, isEncodedImage: image != nil, storedByteCount: storedByteCount)))
        return stored
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
        onEvent?(Event(request: task.request, kind: .imageTaskDidStart))
    }

    @ImagePipelineActor
    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        if case .finished(let result) = event {
            counters.taskFinished(task, with: result)
            if let metrics = task.metrics {
                Self.log(metrics)
                if isRecordingDiagnostics {
                    counters.recordDecodes(from: metrics)
                }
            }
        }
        base.imageTask(task, didReceiveEvent: event, pipeline: pipeline)
        if let onEvent {
            report(event, of: task, to: onEvent)
        }
    }

    /// Passes a task's event on to the screen: every one but the progress
    /// before the data is complete, which arrives once per chunk.
    @ImagePipelineActor
    private func report(_ event: ImageTask.Event, of task: ImageTask, to onEvent: EventHandler) {
        let kind: Event.Kind
        switch event {
        case .progress(let progress):
            guard progress.total > 0, progress.completed == progress.total else { return }
            kind = .progress(progress)
        case .preview:
            kind = .preview
        case .finished(let result):
            kind = .finished(result)
        }
        onEvent(Event(request: task.request, kind: kind))
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

/// A delegate whose every method is the protocol's default: what Nuke does
/// with no delegate.
///
/// A probe forwards to it when the screen has none. A delegate that changes a
/// few hooks calls through it for the rest: Nuke's decompression is internal,
/// so this is the way to reach it.
final class DemoDefaultDelegate: ImagePipeline.Delegate {}

/// A data loader that never goes to the network: it answers from memory,
/// from files, or not at all.
///
/// While the demo is offline, the probe sends the requests of every other
/// loader to a ``DemoFixtureLoader``, and leaves this one's to it, so a
/// screen about such a loader shows the same thing offline. A request for a
/// fixture URL still goes to a fixture loader.
protocol DemoLocalDataLoading: DataLoading {}

extension DemoFixtureLoader: DemoLocalDataLoading {}

/// A decoder of the demo's own that decodes in `decode(_:)`, as the ones
/// Nuke ships do – a decorator around one of them, say – which the probe can
/// wrap and time like them.
///
/// A decoder that decodes through `AsyncImageDecoding` must not conform:
/// wrapped, it would lose the cast the pipeline finds it by.
protocol DemoSynchronousDecoding: ImageDecoding {}

extension DemoPipelineDiagnostics.Queue {
    fileprivate mutating func set(_ queue: TaskQueue) {
        limit = queue.maxConcurrentTaskCount
        isSuspended = queue.isSuspended
    }
}
