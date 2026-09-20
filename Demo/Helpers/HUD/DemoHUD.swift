// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import Observation
import SwiftUI

/// The pipeline HUD: whether it is on, and the figures it shows, for the
/// overlay and the **Pipeline Details** screen its menu opens.
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
    /// How tall the HUD stands, which is the strip every screen leaves free at
    /// its bottom – see ``View/demoHUDRoom()``. The panel measures itself: it
    /// is as tall as the figures it shows.
    var height: CGFloat

    /// Every pipeline alive, oldest first.
    private(set) var pipelines: [Pipeline] = []
    /// Every pipeline added up, the ones that are gone included.
    private(set) var total = DemoPipelineDiagnostics()
    /// What the caches hold, by pipeline; missing until sampled once.
    private(set) var caches: [ObjectIdentifier: DemoPipelineDiagnostics.Caches] = [:]
    private(set) var totalCaches: DemoPipelineDiagnostics.Caches?
    private(set) var display = DemoDisplayMonitor.Figures()
    private(set) var footprint = DemoFootprint()
    /// The pipeline the HUD is held to, or `nil` while it follows whichever
    /// one did something last. The **Pipeline Details** screen sets it, and
    /// it is dropped when that pipeline goes away.
    var pinnedID: ObjectIdentifier?
    private var followedID: ObjectIdentifier?

    @ObservationIgnored private let displayMonitor = DemoDisplayMonitor()
    @ObservationIgnored private var samplingCount = 0
    @ObservationIgnored private var samplingTask: Task<Void, Never>?

    struct Pipeline: Identifiable {
        let id: ObjectIdentifier
        let figures: DemoPipelineDiagnostics
        /// What the details screen works with: the caches it clears and the
        /// task queues it suspends, which are references the configuration
        /// hands out.
        let configuration: ImagePipeline.Configuration
    }

    private init() {
        isVisible = DemoLaunchOptions.current.showsHUD
        isExpanded = DemoLaunchOptions.current.expandsHUD
        height = DemoHUDContainer.pillRoom
    }

    /// The pipeline the overlay shows: the one it is pinned to, or the one it
    /// follows.
    var followed: Pipeline? {
        pipelines.first { $0.id == (pinnedID ?? followedID) }
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
        pipelines = DemoPipelineProbe.liveProbes.map { Pipeline(id: ObjectIdentifier($0), figures: $0.diagnostics, configuration: $0.configuration) }
        total = DemoPipelineProbe.total
        display = displayMonitor.figures
        footprint.sample()
        follow()
    }

    /// Follows the pipeline that did something last, and holds on to it while
    /// it keeps busy, so that two pipelines loading at once don't take turns.
    private func follow() {
        if let pinnedID {
            // A pipeline that is gone can't be shown, so the pin goes with it.
            guard !pipelines.contains(where: { $0.id == pinnedID }) else { return }
            self.pinnedID = nil
        }
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

    /// Reads what the caches hold now rather than waiting for the next sweep:
    /// for the details screen, which has just emptied one.
    func refreshCaches() async {
        await sampleCaches()
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

    // MARK: Figures

    /// The four figures the panel leads with, and the pill the first three of:
    /// what the pipeline it follows is doing, and whether the app keeps up.
    var panelStats: [Stat] {
        Self.stats(followed?.figures ?? DemoPipelineDiagnostics()) + appStats
    }

    /// What a pipeline is doing now, large.
    static func stats(_ figures: DemoPipelineDiagnostics) -> [Stat] {
        [
            Stat(value: "\(figures.activeTaskCount)", caption: "active", tint: figures.activeTaskCount > 0 ? .green : nil),
            Stat(value: hitRate(figures), caption: "hit")
        ]
    }

    /// What the app costs, large: the frames of the last second, and the
    /// memory the system charges it for.
    var appStats: [Stat] {
        let fps = display.framesPerSecond
        return [
            Stat(value: fps.map { String(format: "%.0f", $0) } ?? "–", caption: "fps", tint: (fps ?? .infinity) < 50 ? .orange : nil),
            Stat(value: footprint.current.map { demoByteCount($0) } ?? "–", caption: "memory")
        ]
    }

    /// The three task queues the probe can see, as slots against a limit.
    static func queues(_ figures: DemoPipelineDiagnostics) -> [Queue] {
        [
            ("load", figures.dataLoadingQueue),
            ("decode", figures.decodingQueue),
            ("decomp", figures.decompressingQueue)
        ].map { name, queue in
            Queue(name: name, running: queue.inFlightCount, limit: queue.limit, isSuspended: queue.isSuspended)
        }
    }

    /// The lines for a pipeline, under its stats. Every value starts at the
    /// same column, and the figures that move on their own are padded out to
    /// the width they reach in a busy run, so that what follows stays still.
    static func lines(_ figures: DemoPipelineDiagnostics, caches: DemoPipelineDiagnostics.Caches?) -> [Line] {
        [
            Line(label: "tasks", value: "\(field("\(figures.succeededTaskCount) done", 9)) · \(field("\(figures.cancelledTaskCount) cancelled", 14)) · \(figures.failedTaskCount) failed",
                 tint: figures.failedTaskCount > 0 ? .orange : nil),
            Line(label: "source", value: "\(field("\(figures.networkResponseCount) network", 12)) · \(field("\(figures.diskResponseCount) disk", 9)) · \(figures.servedFromMemoryCount) memory"),
            Line(label: "network", value: "\(field("\(bytes(figures.downloadedByteCount)) down", 14)) · \(bytes(figures.inFlightByteCount)) in flight"),
            // The caches are read every few seconds, so they need no padding.
            Line(label: "memory", value: caches.map { "image \(bytes($0.imageCacheCost, of: $0.imageCacheCostLimit)) · pool \(bytes($0.framePoolCost, of: $0.framePoolCostLimit))" } ?? "…"),
            Line(label: "disk", value: caches.map(disk) ?? "…")
        ]
    }

    private static func disk(_ caches: DemoPipelineDiagnostics.Caches) -> String {
        let parts = [
            caches.dataCacheSize.map { "data \(bytes($0, of: caches.dataCacheSizeLimit ?? 0))" },
            caches.urlCacheDiskUsage.map { "http \(bytes($0, of: caches.urlCacheDiskCapacity ?? 0))" }
        ].compactMap { $0 }
        return parts.isEmpty ? "none" : parts.joined(separator: " · ")
    }

    /// The lines for the app, under its stats: what the display cost, and the
    /// highest the footprint has been.
    var appLines: [Line] {
        let hitch = display.hitchTimeRatio.map { String(format: "%.1f ms/s", $0 * 1000) } ?? "–"
        return [
            Line(label: "display", value: "\(Self.field("\(display.droppedFrameCount) dropped", 12)) · \(Self.field("\(hitch) hitch", 16)) · \(demoDelay(display.longestFrame)) worst",
                 tint: display.droppedFrameCount > 0 ? .orange : nil),
            Line(label: "peak", value: demoByteCount(footprint.peak))
        ]
    }

    /// A figure and the word after it, padded out on its right to the width it
    /// reaches in a busy run: the figures after it on the line stay still as
    /// it grows, and the line still starts where every other line starts.
    private static func field(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    private static func bytes(_ count: some BinaryInteger) -> String {
        demoByteCount(Int64(count))
    }

    /// A cache's cost against its limit; a pipeline without the cache has none.
    private static func bytes(_ count: Int, of limit: Int) -> String {
        limit > 0 ? "\(demoByteCount(count))/\(demoByteCount(limit))" : "none"
    }

    private static func hitRate(_ figures: DemoPipelineDiagnostics) -> String {
        let count = figures.networkResponseCount + figures.diskResponseCount + figures.servedFromMemoryCount
        return count > 0 ? "\(Int((figures.hitRate * 100).rounded()))%" : "–"
    }
}

extension DemoHUD {
    /// One of the figures the HUD leads with, set large enough to read at a
    /// glance: a value and the word under it.
    struct Stat: Identifiable {
        let value: String
        let caption: String
        /// The color of a value worth noticing – work running, frames missed –
        /// or `nil` for the color the rest of the figures are set in.
        var tint: Color?

        var id: String { caption }
    }

    /// A label and the figures after it, as the panel and the **Pipeline
    /// Details** screen both list them.
    struct Line: Identifiable {
        let label: String
        let value: String
        var tint: Color?

        var id: String { label }
    }

    /// A task queue: the work running against the limit, as a row of slots.
    struct Queue: Identifiable {
        let name: String
        /// `nil` where the probe can't see the work.
        let running: Int?
        let limit: Int
        let isSuspended: Bool

        var id: String { name }
    }
}
