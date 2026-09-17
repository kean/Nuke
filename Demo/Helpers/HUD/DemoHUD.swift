// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Observation
import SwiftUI

/// The pipeline HUD: what the overlay, the button in the navigation bar, and
/// the **Pipeline HUD** screen in the Lab share – whether it is on, and the
/// figures it shows.
///
/// It samples only while something on screen asks it to, the way the animation
/// screens sample their players: the counters of ``DemoPipelineProbe`` ten
/// times a second, the caches every 3 seconds (a `DataCache` is measured by
/// listing its directory), the display through a ``DemoDisplayMonitor``, and
/// the footprint through ``DemoFootprint``. With the HUD hidden and the Lab
/// screen closed, no timer and no display link runs.
@MainActor @Observable
final class DemoHUD {
    static let shared = DemoHUD()

    /// Whether the HUD is over the screen. `-demoHUD 1` starts it on.
    var isVisible: Bool
    /// The panel with every figure rather than the pill.
    /// `-demoHUD expanded` starts it open.
    var isExpanded: Bool
    /// The end of the bottom edge the HUD sits at. A drag moves it to the
    /// other one.
    var edge: HorizontalEdge = .leading
    /// The top of a console presented as a sheet, in the window, which the HUD
    /// stays above; `nil` when there is none. `demoConsole` sets it.
    var consoleSheetMinY: CGFloat?

    /// Which pipeline the figures are for. Change it with ``select(_:)``.
    private(set) var selection: Selection = .automatic
    /// The figures of the selection at the last sample.
    private(set) var figures = DemoPipelineDiagnostics()
    /// Every pipeline added up, the ones that are gone included.
    private(set) var total = DemoPipelineDiagnostics()
    /// Every pipeline alive, oldest first.
    private(set) var pipelines: [Pipeline] = []
    /// The pipelines alive, to pick from. Unlike ``pipelines``, it changes
    /// only when a pipeline comes or goes.
    private(set) var choices: [Choice] = []
    /// The pipeline ``Selection/automatic`` is showing.
    private(set) var followed: Choice?
    /// What the caches hold, by what they were sampled for. A key is missing
    /// until its caches have been sampled once.
    private(set) var caches: [CachesKey: DemoPipelineDiagnostics.Caches] = [:]
    private(set) var display = DemoDisplayMonitor.Figures()
    private(set) var footprint = DemoFootprint()
    /// When the figures were last started over; the launch until then.
    private(set) var resetDate = Date()

    private let displayMonitor = DemoDisplayMonitor()
    @ObservationIgnored private var activity: [ObjectIdentifier: Activity] = [:]
    @ObservationIgnored private var samplingCount = 0
    @ObservationIgnored private var samplingTask: Task<Void, Never>?
    @ObservationIgnored private var cachesTask: Task<Void, Never>?

    private init() {
        let options = DemoLaunchOptions.current
        isVisible = options.showsHUD
        isExpanded = options.expandsHUD
    }

    // MARK: Selection

    /// A pipeline to show the figures of.
    enum Selection: Hashable, Sendable {
        /// The pipeline that did something last. It holds on to one for as
        /// long as it keeps busy, so that two pipelines loading at once don't
        /// take turns.
        case automatic
        /// Every pipeline added up: ``DemoPipelineProbe/total``.
        case all
        case pipeline(ObjectIdentifier)
    }

    struct Pipeline: Identifiable, Sendable {
        let id: ObjectIdentifier
        let figures: DemoPipelineDiagnostics
    }

    struct Choice: Hashable, Identifiable, Sendable {
        let id: ObjectIdentifier
        let label: String
    }

    /// What a set of cache figures was sampled for.
    enum CachesKey: Hashable, Sendable {
        case all
        case pipeline(ObjectIdentifier)
    }

    func select(_ selection: Selection) {
        guard selection != self.selection else { return }
        self.selection = selection
        sample()
    }

    /// The name of what the figures are for.
    var title: String {
        switch selection {
        case .automatic: followed?.label ?? "No pipeline"
        case .all: "All Pipelines"
        case .pipeline(let id): choices.first { $0.id == id }?.label ?? "Gone"
        }
    }

    /// What the caches of the selection hold, or `nil` until they have been
    /// sampled.
    var selectedCaches: DemoPipelineDiagnostics.Caches? {
        switch selection {
        case .automatic: followed.flatMap { caches[.pipeline($0.id)] }
        case .all: caches[.all]
        case .pipeline(let id): caches[.pipeline(id)]
        }
    }

    // MARK: Sampling

    /// Starts sampling, unless something has already. Balance every call with
    /// ``stopSampling()``; the views that show the figures call both.
    func startSampling() {
        samplingCount += 1
        guard samplingCount == 1 else { return }
        displayMonitor.start()
        sample()
        samplingTask = Task {
            while true {
                try? await Task.sleep(for: .milliseconds(100))
                // A sleep that ended as the task was cancelled returns normally.
                guard !Task.isCancelled else { return }
                sample()
            }
        }
        restartCacheSampling()
    }

    /// Stops sampling once every ``startSampling()`` is balanced.
    func stopSampling() {
        guard samplingCount > 0 else { return }
        samplingCount -= 1
        guard samplingCount == 0 else { return }
        samplingTask?.cancel()
        samplingTask = nil
        cachesTask?.cancel()
        cachesTask = nil
        displayMonitor.stop()
        display = displayMonitor.figures
    }

    /// Starts the figures of every pipeline, the display, and the peak
    /// footprint over.
    func reset() {
        DemoPipelineProbe.reset()
        displayMonitor.reset()
        footprint.reset()
        // The counts dropping to zero isn't work: they are the new baseline.
        for probe in DemoPipelineProbe.liveProbes {
            activity[ObjectIdentifier(probe)]?.signature = probe.diagnostics.activitySignature
        }
        resetDate = Date()
        sample()
    }

    private func sample() {
        let now = ContinuousClock.now
        let live = DemoPipelineProbe.liveProbes.map { Pipeline(id: ObjectIdentifier($0), figures: $0.diagnostics) }
        for pipeline in live {
            let signature = pipeline.figures.activitySignature
            if let known = activity[pipeline.id] {
                if known.signature != signature {
                    activity[pipeline.id] = Activity(signature: signature, lastActiveAt: now)
                }
            } else {
                // Seen for the first time: busy as of the last work it timed.
                activity[pipeline.id] = Activity(signature: signature, lastActiveAt: pipeline.figures.lastMeasuredAt)
            }
        }
        let ids = Set(live.map(\.id))
        activity = activity.filter { ids.contains($0.key) }
        pipelines = live

        let choices = live.map { Choice(id: $0.id, label: $0.figures.label) }
        if choices != self.choices {
            self.choices = choices
            // A new pipeline's caches, without waiting for the next round.
            if samplingCount > 0 {
                restartCacheSampling()
            }
        }
        follow(live.map(\.id), now: now)
        if case .pipeline(let id) = selection, !ids.contains(id) {
            // The screen that built it has closed.
            selection = .automatic
        }

        total = DemoPipelineProbe.total
        figures = switch selection {
        case .automatic: live.first { $0.id == followed?.id }?.figures ?? DemoPipelineDiagnostics()
        case .all: total
        case .pipeline(let id): live.first { $0.id == id }?.figures ?? DemoPipelineDiagnostics()
        }
        display = displayMonitor.figures
        footprint.sample()
    }

    /// Samples the caches now and every 3 seconds after.
    private func restartCacheSampling() {
        cachesTask?.cancel()
        cachesTask = Task {
            while !Task.isCancelled {
                await sampleCaches()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// The caches of every pipeline, and of all of them, each read on its own:
    /// a cache that two pipelines share counts once in the total.
    private func sampleCaches() async {
        let probes = DemoPipelineProbe.liveProbes
        var caches: [CachesKey: DemoPipelineDiagnostics.Caches] = [:]
        caches[.all] = await DemoPipelineProbe.sampleCaches(of: probes)
        for probe in probes {
            caches[.pipeline(ObjectIdentifier(probe))] = await DemoPipelineProbe.sampleCaches(of: [probe])
        }
        // A round that was started over has a newer one on the way.
        guard !Task.isCancelled else { return }
        self.caches = caches
    }

    /// Moves ``followed`` to the pipeline that did something last, once the
    /// one it follows has been idle for a moment. Among equals, it keeps the
    /// one it has, then takes the newest.
    private func follow(_ ids: [ObjectIdentifier], now: ContinuousClock.Instant) {
        var current = ids.first { $0 == followed?.id }
        if let current, let lastActiveAt = activity[current]?.lastActiveAt, now - lastActiveAt < .milliseconds(1500) {
            return
        }
        for id in ids.reversed() {
            guard let best = current else {
                current = id
                continue
            }
            if let lastActiveAt = activity[id]?.lastActiveAt,
               activity[best]?.lastActiveAt.map({ lastActiveAt > $0 }) ?? true {
                current = id
            }
        }
        let choice = current.flatMap { id in choices.first { $0.id == id } }
        if choice != followed {
            followed = choice
        }
    }

    private struct Activity {
        var signature: Int64
        var lastActiveAt: ContinuousClock.Instant?
    }
}

extension DemoPipelineDiagnostics {
    /// A sum that moves whenever the pipeline does anything the probe counts:
    /// a task, a cache read or write, a chunk of a download, a decode.
    fileprivate var activitySignature: Int64 {
        let counts = createdTaskCount + succeededTaskCount + cancelledTaskCount + failedTaskCount
            + memoryCacheLookupCount + diskCacheLookupCount + diskWriteCount
            + downloadCount + completedDownloadCount + cancelledDownloadCount + failedDownloadCount
            + decoding.count + previewDecoding.count + failedDecodeCount
            + decompression.count + declinedDecompressionCount + encoding.count
        return Int64(counts) + downloadedByteCount + inFlightByteCount + httpCacheByteCount
    }

    /// When the pipeline last finished a piece of work it times.
    fileprivate var lastMeasuredAt: ContinuousClock.Instant? {
        [taskDuration, timeToFirstByte, decoding, previewDecoding, decompression, encoding]
            .compactMap(\.lastMeasuredAt)
            .max()
    }
}
