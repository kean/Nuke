// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Charts
import Nuke
import SwiftUI

/// One pipeline at length: the figures the HUD folds away, the last half
/// minute of its work in charts, what runs on each of its task queues, and what
/// its caches hold, with the controls that empty a cache or suspend a queue.
///
/// A panel rather than a settings screen: one dark surface, and a stack of
/// bands with a hairline between them. A grouped list drew a card around every
/// row and hung a paragraph under every card, which left the chrome more of the
/// screen than the figures had; what those paragraphs said is in the info sheet
/// now, where it is read once rather than scrolled past every time.
///
/// A sheet from the HUD, which stands over every screen, rather than a screen
/// of its own: at the medium detent the screen it was opened over is still
/// there and still loading, which is what an instrument is for. iOS drops the
/// second sheet of a screen, so a screen whose console is a sheet steps aside
/// for it – see ``DemoHUD/openDetails()``.
///
/// Which pipeline it shows is the one the HUD shows, and its title holds the
/// HUD to one when several are alive – see ``DemoHUD/pinnedID``.
struct PipelineDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingInfo = false
    @State private var isShowingOptions = false
    @State private var isShowingPipelines = false

    /// The surface the whole sheet is drawn on: one panel, a shade off black,
    /// rather than a grouped list's cards on a ground of their own.
    private static let panel = Color(white: 0.07)

    var body: some View {
        @Bindable var hud = DemoHUD.shared
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let pipeline = hud.followed {
                        figuresBand(pipeline)
                        Divider()
                        requestsBand(pipeline, hud: hud)
                        Divider()
                        queuesBand(pipeline, hud: hud)
                        Divider()
                        cachesBand(pipeline, hud: hud)
                    } else {
                        noPipelineBand
                    }
                    Divider()
                    appBand(hud)
                    Divider()
                    totalBand(hud)
                    Divider()
                    hudBand(hud)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .background(Self.panel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Self.panel, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    title(hud)
                }
                ToolbarItem(placement: .topBarLeading) {
                    options(hud)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Dark as the HUD's own card is, whatever the app is set in: the sheet
        // is the same instrument at length, and the screen it was opened over
        // goes on showing underneath a partial detent.
        .preferredColorScheme(.dark)
        // Opaque, which a sheet at a partial detent is not by default: this
        // one is a wall of small figures, and over a photo – or worse, over an
        // animation – what shows through washes them out. It also keeps the
        // two detents looking like one sheet.
        .presentationBackground(Self.panel)
        // The screen it was opened over goes on loading underneath, and the
        // charts go on filling while it does.
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await DemoHUD.shared.sampleUntilCancelled()
        }
        .sheet(isPresented: $isShowingInfo) {
            DemoInfoSheet(info: Self.info)
                // Dark as the sheet it is opened from; the info sheet itself
                // belongs to every screen, and follows the app everywhere else.
                // Opaque as well: a sheet over a sheet is translucent by
                // default, and what shows through this one is the toggles of
                // the sheet under it, which the text runs straight across.
                .preferredColorScheme(.dark)
                .presentationBackground(Color(.systemGroupedBackground))
        }
    }

    // MARK: Bands

    /// One band of the panel: its name set small above the figures, and a note
    /// under the name where they need a word of explanation.
    private func band<Content: View>(
        _ name: String,
        _ note: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
    }

    private var noPipelineBand: some View {
        band("Figures") {
            Text("No pipeline has been built yet. Open a screen that loads an image and its figures appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func figuresBand(_ pipeline: DemoHUD.Pipeline) -> some View {
        let figures = pipeline.figures
        return band("Figures", "Since the last reset. Decode and decomp: average · longest.") {
            DemoHUDStats(stats: [
                DemoHUD.Stat(value: "\(figures.activeTaskCount)", caption: "active", tint: figures.activeTaskCount > 0 ? .green : nil),
                DemoHUD.Stat(value: DemoHUD.hitRate(figures), caption: "hit"),
                DemoHUD.Stat(value: "\(figures.succeededTaskCount)", caption: "done"),
                Self.milliseconds(figures.taskDuration.average, caption: "avg task")
            ], size: 25)
            DemoFieldGrid(groups: [Self.taskFields(figures), Self.workFields(figures)], size: 12)
        }
    }

    private func requestsBand(_ pipeline: DemoHUD.Pipeline, hud: DemoHUD) -> some View {
        band("Images finished", "One bar every half second, over the last 30 seconds.") {
            DemoRequestsChart(timeline: hud.timelines[pipeline.id] ?? DemoHUDTimeline())
                .equatable()
        }
    }

    private func queuesBand(_ pipeline: DemoHUD.Pipeline, hud: DemoHUD) -> some View {
        let figures = pipeline.figures
        let ceiling = figures.dataLoadingQueue.limit + figures.decodingQueue.limit + figures.decompressingQueue.limit
        return band("Queues", "Suspend one and the work gathers in front of it.") {
            DemoQueuesChart(timeline: hud.timelines[pipeline.id] ?? DemoHUDTimeline(), ceiling: ceiling)
                .equatable()
            VStack(spacing: 0) {
                ForEach(Self.queues) { kind in
                    queueRow(kind, pipeline: pipeline)
                }
            }
        }
    }

    private func cachesBand(_ pipeline: DemoHUD.Pipeline, hud: DemoHUD) -> some View {
        let configuration = pipeline.configuration
        let caches = hud.caches[pipeline.id]
        let timeline = hud.timelines[pipeline.id] ?? DemoHUDTimeline()
        let urlCache = (configuration.dataLoader as? DataLoader)?.session.configuration.urlCache
        return band("Caches", "The memory cache over 30 seconds, then each against its limit.") {
            // A pipeline without a memory cache – the Lab turns them off – has
            // nothing to chart, and a flat line with no axis reads as broken.
            if caches?.imageCacheCostLimit ?? 0 > 0 {
                DemoMemoryCacheChart(timeline: timeline)
                    .equatable()
            }
            VStack(spacing: 12) {
                DemoCacheMeter(
                    name: "Memory",
                    used: configuration.imageCache == nil ? nil : caches.map(\.imageCacheCost),
                    limit: caches?.imageCacheCostLimit ?? 0,
                    detail: configuration.imageCache == nil ? nil : caches.map { demoCount($0.imageCacheCount, "image") },
                    clear: clearing { configuration.imageCache?.removeAll() }
                )
                DemoCacheMeter(
                    name: "Disk",
                    used: caches?.dataCacheSize,
                    limit: caches?.dataCacheSizeLimit ?? 0,
                    detail: caches?.dataCacheCount.map { demoCount($0, "file") },
                    clear: clearing { configuration.dataCache?.removeAll() }
                )
                DemoCacheMeter(
                    name: "HTTP",
                    used: caches?.urlCacheDiskUsage,
                    limit: caches?.urlCacheDiskCapacity ?? 0,
                    clear: clearing { urlCache?.removeAllCachedResponses() }
                )
                // No button: the pool is shared by every animation playing,
                // whichever pipeline loaded it, and it frees its own frames.
                DemoCacheMeter(
                    name: "Frame pool",
                    used: caches.map(\.framePoolCost),
                    limit: caches?.framePoolCostLimit ?? 0
                )
            }
        }
    }

    private func appBand(_ hud: DemoHUD) -> some View {
        let fps = hud.display.framesPerSecond
        return band("App", "Frames counted on the main thread, capped at 60 Hz.") {
            DemoHUDStats(stats: [
                DemoHUD.Stat(value: fps.map { String(format: "%.0f", $0) } ?? "–", caption: "fps", tint: hud.display.isKeepingUp ? nil : .orange),
                .bytes(hud.footprint.current, caption: "memory"),
                .bytes(hud.footprint.peak, caption: "peak")
            ], size: 25)
            DemoFieldGrid(groups: [hud.displayFields], size: 12)
        }
    }

    private func totalBand(_ hud: DemoHUD) -> some View {
        let total = hud.total
        return band("All pipelines", "Added up, the ones that have gone included.") {
            DemoHUDStats(stats: [
                DemoHUD.Stat(value: "\(total.activeTaskCount)", caption: "active", tint: total.activeTaskCount > 0 ? .green : nil),
                DemoHUD.Stat(value: DemoHUD.hitRate(total), caption: "hit"),
                DemoHUD.Stat(value: "\(total.succeededTaskCount)", caption: "done")
            ], size: 25)
            DemoFieldGrid(groups: [Self.taskFields(total), DemoHUD.byteFields(total, caches: hud.totalCaches)], size: 12)
        }
    }

    private func hudBand(_ hud: DemoHUD) -> some View {
        @Bindable var hud = hud
        return band("HUD", "The card over every screen shows the same figures.") {
            VStack(spacing: 10) {
                Toggle("Show HUD", isOn: $hud.isVisible)
                Toggle("Expanded", isOn: $hud.isExpanded)
                    .disabled(!hud.isVisible)
            }
            .font(.subheadline)
        }
    }

    // MARK: Figures

    /// What else became of the tasks, and where the images came from. The
    /// headline figures above have the ones worth a glance.
    private static func taskFields(_ figures: DemoPipelineDiagnostics) -> DemoHUD.FieldGroup {
        DemoHUD.FieldGroup(
            id: "tasks",
            leading: [
                DemoHUD.Field(label: "cancelled", value: "\(figures.cancelledTaskCount)"),
                DemoHUD.Field(label: "failed", value: "\(figures.failedTaskCount)", tint: figures.failedTaskCount > 0 ? .orange : nil)
            ],
            trailing: [
                DemoHUD.Field(label: "network", value: "\(figures.networkResponseCount)"),
                DemoHUD.Field(label: "disk", value: "\(figures.diskResponseCount)"),
                DemoHUD.Field(label: "memory", value: "\(figures.servedFromMemoryCount)")
            ]
        )
    }

    /// What the downloads cost, and what the work off the main thread took.
    private static func workFields(_ figures: DemoPipelineDiagnostics) -> DemoHUD.FieldGroup {
        DemoHUD.FieldGroup(
            id: "work",
            leading: [
                DemoHUD.Field(label: "downloaded", value: demoByteCount(figures.downloadedByteCount)),
                DemoHUD.Field(label: "in flight", value: demoByteCount(figures.inFlightByteCount))
            ],
            trailing: [
                DemoHUD.Field(label: "decode", value: timing(figures.decoding)),
                DemoHUD.Field(label: "decomp", value: timing(figures.decompression))
            ]
        )
    }

    /// A timing as the two figures worth having: the average and the longest.
    private static func timing(_ timing: DemoPipelineDiagnostics.Timing) -> String {
        guard timing.count > 0 else { return "–" }
        return "\(number(timing.average)) · \(number(timing.max)) ms"
    }

    private static func number(_ seconds: TimeInterval) -> String {
        String(format: seconds < 0.01 ? "%.1f" : "%.0f", seconds * 1000)
    }

    /// A duration as a headline figure, with the unit set apart from it.
    private static func milliseconds(_ seconds: TimeInterval, caption: String) -> DemoHUD.Stat {
        guard seconds > 0 else { return DemoHUD.Stat(value: "–", caption: caption) }
        return DemoHUD.Stat(value: number(seconds), unit: "ms", caption: caption)
    }

    // MARK: Queues

    /// One of the pipeline's task queues: where it is on the configuration,
    /// and where the probe counts the work running on it. The probe can't see
    /// processing, as processors come with the request.
    private struct QueueKind: Identifiable {
        let title: String
        let queue: KeyPath<ImagePipeline.Configuration, TaskQueue>
        var figures: KeyPath<DemoPipelineDiagnostics, DemoPipelineDiagnostics.Queue>?

        var id: String { title }
    }

    private static let queues = [
        QueueKind(title: "Data loading", queue: \.dataLoadingQueue, figures: \.dataLoadingQueue),
        QueueKind(title: "Decoding", queue: \.imageDecodingQueue, figures: \.decodingQueue),
        QueueKind(title: "Processing", queue: \.imageProcessingQueue),
        QueueKind(title: "Decompressing", queue: \.imageDecompressingQueue, figures: \.decompressingQueue),
        QueueKind(title: "Encoding", queue: \.imageEncodingQueue, figures: \.encodingQueue)
    ]

    private func queueRow(_ kind: QueueKind, pipeline: DemoHUD.Pipeline) -> some View {
        let queue = pipeline.configuration[keyPath: kind.queue]
        let running = kind.figures.flatMap { pipeline.figures[keyPath: $0].inFlightCount }
        let limit = queue.maxConcurrentTaskCount
        let isSuspended = queue.isSuspended
        return HStack(spacing: 10) {
            Text(kind.title)
                .font(.subheadline)
                .foregroundStyle(isSuspended ? Color.orange : .primary)
            Spacer(minLength: 4)
            if let running, (1...8).contains(limit) {
                DemoQueueSlots(
                    running: running,
                    limit: limit,
                    isSuspended: isSuspended,
                    size: CGSize(width: 5, height: 11),
                    tint: DemoChartRamp.single
                )
            }
            Text(verbatim: "\(running.map { "\($0)" } ?? "–")/\(limit)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(isSuspended ? Color.orange : .secondary)
                .frame(width: 30, alignment: .trailing)
            Button {
                queue.isSuspended.toggle()
            } label: {
                Image(systemName: isSuspended ? "play.fill" : "pause.fill")
                    .font(.system(size: 10))
                    // Quiet at rest and orange while it holds the work back,
                    // which is the state worth noticing.
                    .foregroundStyle(isSuspended ? Color.orange : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isSuspended ? Color.orange.opacity(0.20) : Color.primary.opacity(0.09)))
                    // The circle is the size the row reads at; what answers a
                    // finger is the whole of the row's height beside it.
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSuspended ? "Resume \(kind.title)" : "Suspend \(kind.title)")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(running.map { "\($0)" } ?? "unknown") of \(limit) running" + (isSuspended ? ", suspended" : ""))
    }

    /// Empties a cache and reads the figures again, rather than leaving them
    /// as they were until the next sweep.
    private func clearing(_ action: @escaping () -> Void) -> () -> Void {
        {
            action()
            Task { await DemoHUD.shared.refreshCaches() }
        }
    }

    // MARK: Title and options

    /// What the sheet is titled: the pipeline it shows, and, when several are
    /// alive, the list that holds both sheet and HUD to one of them.
    private func title(_ hud: DemoHUD) -> some View {
        let label = hud.followed?.figures.label ?? "Pipeline Details"
        return Group {
            if hud.pipelines.count > 1 {
                Button {
                    isShowingPipelines = true
                } label: {
                    HStack(spacing: 3) {
                        Text(label)
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                }
                .accessibilityLabel("Pipeline, \(label)")
                .accessibilityHint("Picks the pipeline this sheet and the HUD show")
                .demoOptionsPopover(isPresented: $isShowingPipelines) {
                    DemoOptionRow(title: "Active", systemImage: "bolt", isChosen: hud.pinnedID == nil) {
                        isShowingPipelines = false
                        hud.pinnedID = nil
                    }
                    ForEach(hud.pipelines) { pipeline in
                        DemoOptionRow(title: pipeline.figures.label, systemImage: "pin", isChosen: hud.pinnedID == pipeline.id) {
                            isShowingPipelines = false
                            hud.pinnedID = pipeline.id
                        }
                    }
                }
            } else {
                Text(label)
                    .font(.headline)
            }
        }
    }

    /// The sheet's own options. A popover rather than a menu: a menu is
    /// presented by UIKit and follows the window, so inside a sheet held dark
    /// it comes up light.
    private func options(_ hud: DemoHUD) -> some View {
        Button {
            isShowingOptions = true
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Options")
        .demoOptionsPopover(isPresented: $isShowingOptions) {
            DemoOptionRow(title: "Reset Figures", systemImage: "arrow.counterclockwise") {
                isShowingOptions = false
                hud.reset()
            }
            if hud.pinnedID != nil {
                DemoOptionRow(title: "Follow Active Pipeline", systemImage: "pin.slash") {
                    isShowingOptions = false
                    hud.pinnedID = nil
                }
            }
            DemoOptionRow(title: "About These Figures", systemImage: "questionmark") {
                isShowingOptions = false
                isShowingInfo = true
            }
        }
    }

    private static let info = DemoInfo(
        "Pipeline Details",
        "One pipeline: what it has done since the last reset, as the probe it is built with counts it; the last half minute of its work in charts; what runs on each of its task queues; and what its caches hold, with the controls that empty one. The HUD over every screen shows the same figures, folded down to what fits.",
        points: [
            .init("Which pipeline", "The HUD follows the pipeline that did something last, and holds on to it while it keeps busy. Pick one from the title and both sheet and HUD stay with it; the HUD shows a pin while they do."),
            .init("The charts", "The last 30 seconds, a point every half second. They are drawn in one hue, light to dark, because both stacks have an order: the stages work passes through, and how far the pipeline had to go for an image."),
            .init("Source", "Where the images came from: a download, `URLCache` and fixtures included; `DataCache`; or the memory cache, with or without a task. Hit is the share that didn't download."),
            .init("Queues", "The work running on each queue against its limit, a slot apiece. `TaskQueue` makes its limit and suspension public and keeps what waits to itself, so the probe counts what it sees running; processing it can't see at all, as processors come with the request. A suspended queue holds its work back on every screen this pipeline serves, and the HUD shows it in orange."),
            .init("Caches", "The memory cache, the `DataCache`, the `URLCache` of the loader's session, and the shared frame pool, each against its limit. The memory figures are read with the counters; the disk ones every 3 seconds, as a `DataCache` is measured by listing its directory. A cache that two pipelines share is emptied for both, and the frame pool is shared by every animation playing, whichever pipeline loaded it."),
            .init("The app", "The frames of the last second, counted by a `CADisplayLink` on the main thread. It is driven at 60 Hz, on a 120 Hz display as well, so 60 fps is as high as this goes."),
            .init("Blind spots", "Work waiting in a queue, processing, and frames the render server drops on its own.")
        ]
    )
}
