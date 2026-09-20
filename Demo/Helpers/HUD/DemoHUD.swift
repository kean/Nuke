// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import Observation
import SwiftUI

/// The pipeline HUD: whether it is on, and the figures it shows, for the
/// card over every screen and the **Pipeline Details** sheet its info button
/// opens.
///
/// It samples only while something on screen asks it to: the probe's counters
/// ten times a second, and the caches every 3 seconds, as a `DataCache` is
/// measured by listing its directory. Hidden, it runs nothing.
@MainActor @Observable
final class DemoHUD {
    static let shared = DemoHUD()

    /// Whether the HUD is over the screen. `-demoHUD 1` starts it on.
    var isVisible: Bool
    /// The card opened out rather than folded into its pill. `-demoHUD
    /// expanded` starts it open.
    var isExpanded: Bool
    /// The corner the card stands in. It is dragged from one corner to another,
    /// and the card's options move it too. `-demoHUDCorner <corner>` starts it
    /// there.
    var corner: Corner
    /// The top of a console presented as a sheet, in the window, which the HUD
    /// stays above; `nil` when there is none. `demoConsole` sets it.
    var consoleSheetMinY: CGFloat?
    /// How tall the card stands, measured as it grows: what a bottom corner
    /// needs to clear a console sheet. The HUD floats over the screen rather
    /// than taking a strip of it, so no screen leaves room for it.
    var height: CGFloat

    /// Every pipeline alive, oldest first.
    private(set) var pipelines: [Pipeline] = []
    /// Every pipeline added up, the ones that are gone included.
    private(set) var total = DemoPipelineDiagnostics()
    /// What the caches hold, by pipeline; missing until sampled once. The
    /// memory figures are read on every tick, the disk ones every few seconds.
    private(set) var caches: [ObjectIdentifier: DemoPipelineDiagnostics.Caches] = [:]
    private(set) var totalCaches: DemoPipelineDiagnostics.Caches?
    /// The last half minute of each pipeline, which the charts on the **Pipeline
    /// Details** sheet are drawn from.
    private(set) var timelines: [ObjectIdentifier: DemoHUDTimeline] = [:]
    private(set) var display = DemoDisplayMonitor.Figures()
    private(set) var footprint = DemoFootprint()
    /// The pipeline the HUD is held to, or `nil` while it follows whichever
    /// one did something last. The **Pipeline Details** sheet sets it, and it
    /// is dropped when that pipeline goes away.
    var pinnedID: ObjectIdentifier?
    private var followedID: ObjectIdentifier?

    @ObservationIgnored private let displayMonitor = DemoDisplayMonitor()
    @ObservationIgnored private var samplingCount = 0
    @ObservationIgnored private var samplingTask: Task<Void, Never>?
    @ObservationIgnored private var tick = 0
    /// The pipelines whose disk caches have been read at least once, so that a
    /// pipeline that has just appeared is swept right away. The memory figures
    /// alone don't say: they are filled in on the first tick.
    @ObservationIgnored private var diskSweptIDs: Set<ObjectIdentifier> = []

    /// How often the counters are read.
    private static let tickInterval = Duration.milliseconds(100)
    /// The ticks between two points of a timeline.
    private static let ticksPerPoint = Int(DemoHUDTimeline.interval * 1000) / 100
    /// The ticks between two sweeps of the disk caches, which are read by
    /// listing a directory.
    private static let ticksPerDiskSweep = 30

    struct Pipeline: Identifiable {
        let id: ObjectIdentifier
        let figures: DemoPipelineDiagnostics
        /// What the details sheet works with: the caches it clears and the
        /// task queues it suspends, which are references the configuration
        /// hands out.
        let configuration: ImagePipeline.Configuration
    }

    private init() {
        isVisible = DemoLaunchOptions.current.showsHUD
        isExpanded = DemoLaunchOptions.current.expandsHUD
        corner = DemoLaunchOptions.current.hudCorner
        height = DemoHUDContainer.pillRoom
    }

    /// The pipeline the overlay shows: the one it is pinned to, or the one it
    /// follows.
    var followed: Pipeline? {
        pipelines.first { $0.id == (pinnedID ?? followedID) }
    }

    /// Samples for as long as the calling task runs. The card and the details
    /// sheet can both call it: the first starts the sampling, the last stops it.
    func sampleUntilCancelled() async {
        samplingCount += 1
        if samplingCount == 1 {
            displayMonitor.start()
            samplingTask = Task {
                while !Task.isCancelled {
                    sample()
                    if tick % Self.ticksPerDiskSweep == 0 || pipelines.contains(where: { !diskSweptIDs.contains($0.id) }) {
                        await sampleCaches()
                    }
                    try? await Task.sleep(for: Self.tickInterval)
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

    /// Starts the figures of every pipeline, the display, the peak footprint,
    /// and the charts' window over.
    func reset() {
        DemoPipelineProbe.reset()
        displayMonitor.reset()
        footprint.reset()
        timelines.removeAll()
        sample()
    }

    private func sample() {
        let probes = DemoPipelineProbe.liveProbes
        pipelines = probes.map { Pipeline(id: ObjectIdentifier($0), figures: $0.diagnostics, configuration: $0.configuration) }
        total = DemoPipelineProbe.total
        display = displayMonitor.figures
        footprint.sample()
        sampleMemoryCaches(of: probes)
        follow()
        tick += 1
        if tick % Self.ticksPerPoint == 0 {
            record()
        }
    }

    /// Adds a point to every live pipeline's timeline.
    private func record() {
        var recorded: [ObjectIdentifier: DemoHUDTimeline] = [:]
        for pipeline in pipelines {
            var timeline = timelines[pipeline.id] ?? DemoHUDTimeline()
            timeline.record(pipeline.figures, imageCacheCost: caches[pipeline.id]?.imageCacheCost ?? 0)
            recorded[pipeline.id] = timeline
        }
        // A pipeline that is gone takes its window with it.
        timelines = recorded
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
    /// for the details sheet, which has just emptied one.
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
        diskSweptIDs = Set(caches.keys)
    }

    /// Reads what the memory caches hold, which every tick can afford, and
    /// leaves the disk figures of the last sweep where they were. It is what
    /// keeps the memory line of the HUD and the cache chart of the details
    /// moving between the sweeps.
    private func sampleMemoryCaches(of probes: [DemoPipelineProbe]) {
        var updated: [ObjectIdentifier: DemoPipelineDiagnostics.Caches] = [:]
        for probe in probes {
            let id = ObjectIdentifier(probe)
            var caches = self.caches[id] ?? DemoPipelineDiagnostics.Caches()
            caches.setMemoryFigures(DemoPipelineProbe.memoryCaches(of: [probe]))
            updated[id] = caches
        }
        caches = updated
        var total = totalCaches ?? DemoPipelineDiagnostics.Caches()
        total.setMemoryFigures(DemoPipelineProbe.memoryCaches(of: probes))
        totalCaches = total
    }

    // MARK: Details

    /// Whether the **Pipeline Details** sheet is up. The HUD presents it, over
    /// whatever screen is on display.
    var isShowingDetails = false
    /// Whether a screen's console is stepping aside for the details. iOS drops
    /// the second sheet of a screen, so a console that is a sheet goes first
    /// and comes back when the details close – see ``View/demoConsole(collapsedHeight:info:console:)``.
    private(set) var isConsoleSteppingAside = false

    /// Opens the details, after the console of the screen below has stepped
    /// aside if it has one.
    func openDetails() {
        guard !isShowingDetails, !isConsoleSteppingAside else { return }
        guard consoleSheetMinY != nil else {
            isShowingDetails = true
            return
        }
        isConsoleSteppingAside = true
        Task {
            // If nothing answers – a console already on its way out, or one
            // that left its figure behind – the details open anyway rather
            // than waiting on a sheet that isn't there, which would leave the
            // info button doing nothing from then on.
            try? await Task.sleep(for: .milliseconds(600))
            guard isConsoleSteppingAside else { return }
            isConsoleSteppingAside = false
            isShowingDetails = true
        }
    }

    /// Called by a console sheet once it has gone, to say the way is clear.
    /// The details wait out the rest of the dismissal: a sheet asked for while
    /// another is still going is dropped rather than queued.
    func consoleDidHide() {
        guard isConsoleSteppingAside else { return }
        isConsoleSteppingAside = false
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            isShowingDetails = true
        }
    }

    // MARK: Figures

    /// The four figures the open card leads with, and the folded one the first
    /// three of: what the pipeline it follows is doing, and whether the app
    /// keeps up.
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
            Stat(value: fps.map { String(format: "%.0f", $0) } ?? "–", caption: "fps", tint: display.isKeepingUp ? nil : .orange),
            Stat(value: footprint.current.map { demoByteCount($0) } ?? "–", caption: "memory")
        ]
    }

    /// The task queues an image passes through, as slots against a limit. The
    /// probe counts the work running on three of them; processors come with the
    /// request, so processing is a limit and a switch and no count.
    static func queues(_ figures: DemoPipelineDiagnostics) -> [Queue] {
        [
            ("load", figures.dataLoadingQueue),
            ("decode", figures.decodingQueue),
            ("proc", figures.processingQueue),
            ("decomp", figures.decompressingQueue)
        ].map { name, queue in
            Queue(name: name, running: queue.inFlightCount, limit: queue.limit, isSuspended: queue.isSuspended)
        }
    }

    /// The lines for a pipeline, under its figures. Every value starts at the
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

    /// What a busy main thread cost the display, which the card and the sheet
    /// both show.
    var displayLine: Line {
        let hitch = display.hitchTimeRatio.map { String(format: "%.1f ms/s", $0 * 1000) } ?? "–"
        return Line(label: "display", value: "\(Self.field("\(display.droppedFrameCount) dropped", 12)) · \(Self.field("\(hitch) hitch", 16)) · \(demoDelay(display.longestFrame)) worst",
                    tint: display.droppedFrameCount > 0 ? .orange : nil)
    }

    /// The lines for the app, under its figures. The sheet sets the peak
    /// beside the footprint instead, where the two read together.
    var appLines: [Line] {
        [displayLine, Line(label: "peak", value: demoByteCount(footprint.peak))]
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

    /// The share of the images that didn't download, as a percentage, or a
    /// dash before any of them have arrived.
    static func hitRate(_ figures: DemoPipelineDiagnostics) -> String {
        let count = figures.networkResponseCount + figures.diskResponseCount + figures.servedFromMemoryCount
        return count > 0 ? "\(Int((figures.hitRate * 100).rounded()))%" : "–"
    }
}

extension DemoHUD {
    /// A corner of the screen the card stands in, which it is dragged between.
    enum Corner: String, CaseIterable, Identifiable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        /// The corner of the half the card was let go in.
        init(isTop: Bool, isLeading: Bool) {
            switch (isTop, isLeading) {
            case (true, true): self = .topLeading
            case (true, false): self = .topTrailing
            case (false, true): self = .bottomLeading
            case (false, false): self = .bottomTrailing
            }
        }

        var id: String { rawValue }
        var isTop: Bool { self == .topLeading || self == .topTrailing }
        var isLeading: Bool { self == .topLeading || self == .bottomLeading }

        var alignment: Alignment {
            switch self {
            case .topLeading: .topLeading
            case .topTrailing: .topTrailing
            case .bottomLeading: .bottomLeading
            case .bottomTrailing: .bottomTrailing
            }
        }

        /// What the card's options call it: the words a screen is described
        /// in, rather than the leading and trailing a layout is written in.
        var title: String {
            switch self {
            case .topLeading: "Top Left"
            case .topTrailing: "Top Right"
            case .bottomLeading: "Bottom Left"
            case .bottomTrailing: "Bottom Right"
            }
        }

        var systemImage: String {
            switch self {
            case .topLeading: "arrow.up.left"
            case .topTrailing: "arrow.up.right"
            case .bottomLeading: "arrow.down.left"
            case .bottomTrailing: "arrow.down.right"
            }
        }
    }

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

    /// A label and the figures after it, as the card and the **Pipeline
    /// Details** sheet both list them.
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
