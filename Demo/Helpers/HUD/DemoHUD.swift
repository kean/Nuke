// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Observation
import SwiftUI

/// The pipeline HUD: whether it is on, and the figures it shows, for the
/// overlay, the gauge in the navigation bar, and the **Pipeline HUD** screen.
///
/// It samples only while something on screen asks it to: the probe's counters
/// ten times a second, and the caches every 3 seconds, as a `DataCache` is
/// measured by listing its directory. Hidden, it runs nothing.
@MainActor @Observable
final class DemoHUD {
    static let shared = DemoHUD()

    /// Whether the HUD is over the screen. `-demoHUD 1` starts it on.
    var isVisible: Bool
    /// The panel rather than the pill. `-demoHUD expanded` starts it open.
    var isExpanded: Bool
    /// The top of a console presented as a sheet, in the window, which the HUD
    /// stays above; `nil` when there is none. `demoConsole` sets it.
    var consoleSheetMinY: CGFloat?

    /// Every pipeline alive, oldest first.
    private(set) var pipelines: [Pipeline] = []
    /// Every pipeline added up, the ones that are gone included.
    private(set) var total = DemoPipelineDiagnostics()
    /// What the caches hold, by pipeline; missing until sampled once.
    private(set) var caches: [ObjectIdentifier: DemoPipelineDiagnostics.Caches] = [:]
    private(set) var totalCaches: DemoPipelineDiagnostics.Caches?
    private(set) var display = DemoDisplayMonitor.Figures()
    private(set) var footprint = DemoFootprint()
    private var followedID: ObjectIdentifier?

    @ObservationIgnored private let displayMonitor = DemoDisplayMonitor()
    @ObservationIgnored private var samplingCount = 0
    @ObservationIgnored private var samplingTask: Task<Void, Never>?

    struct Pipeline: Identifiable {
        let id: ObjectIdentifier
        let figures: DemoPipelineDiagnostics
    }

    private init() {
        isVisible = DemoLaunchOptions.current.showsHUD
        isExpanded = DemoLaunchOptions.current.expandsHUD
    }

    /// The pipeline the overlay shows.
    var followed: Pipeline? {
        pipelines.first { $0.id == followedID }
    }

    /// Samples for as long as the calling task runs. The overlay and the Lab
    /// screen can both call it: the first starts the sampling, the last stops it.
    func sampleUntilCancelled() async {
        samplingCount += 1
        if samplingCount == 1 {
            displayMonitor.start()
            samplingTask = Task {
                var tick = 0
                while !Task.isCancelled {
                    sample()
                    if tick % 30 == 0 || pipelines.contains(where: { caches[$0.id] == nil }) {
                        await sampleCaches()
                    }
                    tick += 1
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
        await demoWaitUntilCancelled()
        samplingCount -= 1
        if samplingCount == 0 {
            samplingTask?.cancel()
            displayMonitor.stop()
        }
    }

    /// Starts the figures of every pipeline, the display, and the peak
    /// footprint over.
    func reset() {
        DemoPipelineProbe.reset()
        displayMonitor.reset()
        footprint.reset()
        sample()
    }

    private func sample() {
        pipelines = DemoPipelineProbe.liveProbes.map { Pipeline(id: ObjectIdentifier($0), figures: $0.diagnostics) }
        total = DemoPipelineProbe.total
        display = displayMonitor.figures
        footprint.sample()
        follow()
    }

    /// Follows the pipeline that did something last, and holds on to it while
    /// it keeps busy, so that two pipelines loading at once don't take turns.
    private func follow() {
        let now = ContinuousClock.now
        func lastActive(_ pipeline: Pipeline) -> ContinuousClock.Instant? {
            pipeline.figures.activeTaskCount > 0 ? now : pipeline.figures.taskDuration.lastMeasuredAt
        }
        if let followed, let instant = lastActive(followed), now - instant < .milliseconds(1500) {
            return
        }
        // Among equals, the first wins: the one it follows, then the newest.
        followedID = ((followed.map { [$0] } ?? []) + pipelines.reversed()).max { lhs, rhs in
            guard let rhs = lastActive(rhs) else { return false }
            return lastActive(lhs).map { $0 < rhs } ?? true
        }?.id
    }

    private func sampleCaches() async {
        let probes = DemoPipelineProbe.liveProbes
        var caches: [ObjectIdentifier: DemoPipelineDiagnostics.Caches] = [:]
        for probe in probes {
            caches[ObjectIdentifier(probe)] = await DemoPipelineProbe.sampleCaches(of: [probe])
        }
        // A cache that two pipelines share counts once.
        totalCaches = await DemoPipelineProbe.sampleCaches(of: probes)
        self.caches = caches
    }

    // MARK: Lines

    /// The lines for a pipeline. A figure padded to the width it reaches in a
    /// busy run keeps the words after it still.
    static func lines(_ figures: DemoPipelineDiagnostics, caches: DemoPipelineDiagnostics.Caches?) -> [(String, String)] {
        let queues = [
            ("load", figures.dataLoadingQueue),
            ("decode", figures.decodingQueue),
            ("decomp", figures.decompressingQueue)
        ].map { name, queue in
            "\(name) \(queue.inFlightCount.map { "\($0)" } ?? "–")/\(queue.limit)\(queue.isSuspended ? " paused" : "")"
        }
        return [
            ("tasks", "\(pad(figures.activeTaskCount, 3)) active · \(pad(figures.succeededTaskCount, 4)) done · \(pad(figures.cancelledTaskCount, 3)) cancelled"
                + (figures.failedTaskCount > 0 ? " · \(figures.failedTaskCount) failed" : "")),
            ("source", "\(pad(figures.networkResponseCount, 3)) network · \(pad(figures.diskResponseCount, 3)) disk · \(pad(figures.servedFromMemoryCount, 3)) memory · \(hitRate(figures)) hit"),
            ("queues", queues.joined(separator: " · ")),
            ("network", "\(bytes(figures.downloadedByteCount)) down · \(bytes(figures.inFlightByteCount)) in flight"),
            ("memory", caches.map { "image \(bytes($0.imageCacheCost, of: $0.imageCacheCostLimit)) · pool \(bytes($0.framePoolCost, of: $0.framePoolCostLimit))" } ?? "…"),
            ("disk", caches.map(disk) ?? "…")
        ]
    }

    private static func disk(_ caches: DemoPipelineDiagnostics.Caches) -> String {
        let parts = [
            caches.dataCacheSize.map { "data \(bytes($0, of: caches.dataCacheSizeLimit ?? 0))" },
            caches.urlCacheDiskUsage.map { "http \(bytes($0, of: caches.urlCacheDiskCapacity ?? 0))" }
        ].compactMap { $0 }
        return parts.isEmpty ? "none" : parts.joined(separator: " · ")
    }

    /// The lines for the app: its memory, and whether the display keeps up.
    var appLines: [(String, String)] {
        let fps = display.framesPerSecond.map { String(format: "%.1f", $0) } ?? "–"
        return [
            ("footprint", "\(footprint.current.map { Self.bytes($0) } ?? "–") · peak \(Self.bytes(footprint.peak))"),
            ("display", "\(demoPad(fps, to: 5)) fps · \(Self.pad(display.droppedFrameCount, 4)) dropped · \(demoDelay(display.longestFrame)) worst")
        ]
    }

    /// The pill: whether anything is loading, whether the caches answer, and
    /// whether the screen keeps up.
    var headline: String {
        let figures = followed?.figures ?? DemoPipelineDiagnostics()
        let fps = display.framesPerSecond.map { String(format: "%.0f", $0) } ?? "–"
        return "\(Self.pad(figures.activeTaskCount, 3)) active · \(Self.hitRate(figures)) hit · \(demoPad(fps, to: 3)) fps"
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        demoPad("\(value)", to: width)
    }

    private static func bytes(_ count: some BinaryInteger) -> String {
        demoPad(demoByteCount(Int64(count)), to: 8)
    }

    /// A cache's cost against its limit; a pipeline without the cache has none.
    private static func bytes(_ count: Int, of limit: Int) -> String {
        limit > 0 ? "\(demoPad(demoByteCount(count), to: 7))/\(demoByteCount(limit))" : "none"
    }

    private static func hitRate(_ figures: DemoPipelineDiagnostics) -> String {
        let count = figures.networkResponseCount + figures.diskResponseCount + figures.servedFromMemoryCount
        return demoPad(count > 0 ? "\(Int((figures.hitRate * 100).rounded()))%" : "–", to: 4)
    }
}
