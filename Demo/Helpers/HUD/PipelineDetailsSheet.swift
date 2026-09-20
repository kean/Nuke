// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Charts
import Nuke
import SwiftUI

/// One pipeline at length: the figures the HUD folds away, the last half
/// minute of its work in charts, what runs on each of its task queues, and what its
/// caches hold, with the controls that empty a cache or suspend a queue.
///
/// A sheet from the HUD, which stands over every screen, rather than a screen
/// of its own: at the medium detent the screen it was opened over is still
/// there and still loading, which is what an instrument is for. iOS drops the
/// second sheet of a screen, so a screen whose console is a sheet steps aside
/// for it – see ``DemoHUD/openDetails()``.
///
/// Which pipeline it shows is the one the HUD shows, and its picker holds the
/// HUD to one when several are alive – see ``DemoHUD/pinnedID``.
struct PipelineDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingInfo = false

    var body: some View {
        @Bindable var hud = DemoHUD.shared
        return NavigationStack {
            List {
                if let pipeline = hud.followed {
                    figuresSection(pipeline)
                    requestsSection(pipeline, hud: hud)
                    queuesSection(pipeline, hud: hud)
                    cachesSection(pipeline, hud: hud)
                } else {
                    Section {
                        Text("No pipeline has been built yet. Open a screen that loads an image and its figures appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                appSection(hud)
                totalSection(hud)
                hudSection(hud)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    PipelineTitle(hud: hud)
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
        .presentationBackground(Color(.systemGroupedBackground))
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

    private func options(_ hud: DemoHUD) -> some View {
        Menu {
            Button("Reset Figures", systemImage: "arrow.counterclockwise") {
                hud.reset()
            }
            if hud.pinnedID != nil {
                Button("Follow Active Pipeline", systemImage: "pin.slash") {
                    hud.pinnedID = nil
                }
            }
            Button("About These Figures", systemImage: "questionmark") {
                isShowingInfo = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Options")
    }

    // MARK: Figures

    private func figuresSection(_ pipeline: DemoHUD.Pipeline) -> some View {
        let figures = pipeline.figures
        return Section {
            DemoFigureGrid(figures: [
                .init("active", "\(figures.activeTaskCount)", tint: figures.activeTaskCount > 0 ? .green : nil),
                .init("hit", DemoHUD.hitRate(figures)),
                .init("done", "\(figures.succeededTaskCount)"),
                .init("cancelled", "\(figures.cancelledTaskCount)"),
                .init("failed", "\(figures.failedTaskCount)", tint: figures.failedTaskCount > 0 ? .orange : nil),
                .init("avg task", Self.milliseconds(figures.taskDuration.average))
            ])
            .demoFiguresRow()
            DemoHUDLines(groups: [Self.workLines(figures)])
                .demoFiguresRow()
        } header: {
            Text("Figures")
        } footer: {
            Text("What this pipeline has done since the last reset, as the probe it is built with counts it. Hit is the share of the images that didn't download.")
        }
    }

    /// The lines under the headline figures: where the images came from, what
    /// the downloads cost, and how long the work off the main thread took.
    private static func workLines(_ figures: DemoPipelineDiagnostics) -> [DemoHUD.Line] {
        [
            DemoHUD.Line(label: "source", value: "\(figures.networkResponseCount) network · \(figures.diskResponseCount) disk · \(figures.servedFromMemoryCount) memory"),
            DemoHUD.Line(label: "network", value: "\(demoByteCount(figures.downloadedByteCount)) down · \(demoByteCount(figures.inFlightByteCount)) in flight"),
            DemoHUD.Line(label: "decode", value: timing(figures.decoding)),
            DemoHUD.Line(label: "decomp", value: timing(figures.decompression))
        ]
    }

    private static func timing(_ timing: DemoPipelineDiagnostics.Timing) -> String {
        guard timing.count > 0 else { return "–" }
        return "avg \(milliseconds(timing.average)) · max \(milliseconds(timing.max)) · \(timing.count)"
    }

    private static func milliseconds(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "–" }
        return String(format: seconds < 0.01 ? "%.1f ms" : "%.0f ms", seconds * 1000)
    }

    // MARK: Requests

    private func requestsSection(_ pipeline: DemoHUD.Pipeline, hud: DemoHUD) -> some View {
        Section {
            DemoRequestsChart(timeline: hud.timelines[pipeline.id] ?? DemoHUDTimeline())
                .equatable()
                .demoFiguresRow()
        } header: {
            Text("Requests")
        } footer: {
            Text("Every image the pipeline finished, stacked by where it came from. The darker the stack, the further the pipeline had to go for them: the memory cache, then the disk cache, then a download.")
        }
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
        QueueKind(title: "Data Loading", queue: \.dataLoadingQueue, figures: \.dataLoadingQueue),
        QueueKind(title: "Decoding", queue: \.imageDecodingQueue, figures: \.decodingQueue),
        QueueKind(title: "Processing", queue: \.imageProcessingQueue),
        QueueKind(title: "Decompressing", queue: \.imageDecompressingQueue, figures: \.decompressingQueue),
        QueueKind(title: "Encoding", queue: \.imageEncodingQueue, figures: \.encodingQueue)
    ]

    private func queuesSection(_ pipeline: DemoHUD.Pipeline, hud: DemoHUD) -> some View {
        let figures = pipeline.figures
        let ceiling = figures.dataLoadingQueue.limit + figures.decodingQueue.limit + figures.decompressingQueue.limit
        return Section {
            DemoQueuesChart(timeline: hud.timelines[pipeline.id] ?? DemoHUDTimeline(), ceiling: ceiling)
                .equatable()
                .demoFiguresRow()
            ForEach(Self.queues) { kind in
                queueRow(kind, pipeline: pipeline)
            }
        } header: {
            Text("Queues")
        } footer: {
            Text("The work running on each queue against its limit, as the probe counts it. Suspend one and the tasks gather in front of it, on every screen this pipeline serves, until it is resumed: the HUD shows a suspended queue in orange.")
        }
    }

    private func queueRow(_ kind: QueueKind, pipeline: DemoHUD.Pipeline) -> some View {
        let queue = pipeline.configuration[keyPath: kind.queue]
        let running = kind.figures.flatMap { pipeline.figures[keyPath: $0].inFlightCount }
        let limit = queue.maxConcurrentTaskCount
        return HStack(spacing: 10) {
            Text(kind.title)
                .font(.subheadline)
            Spacer(minLength: 4)
            if let running, (1...8).contains(limit) {
                DemoQueueSlots(
                    running: running,
                    limit: limit,
                    isSuspended: queue.isSuspended,
                    size: CGSize(width: 5, height: 10),
                    tint: .accentColor
                )
            }
            DemoMonoLabel("\(running.map { "\($0)" } ?? "–")/\(limit)", tint: queue.isSuspended ? .orange : .secondary)
            Button {
                queue.isSuspended.toggle()
            } label: {
                Image(systemName: queue.isSuspended ? "play.fill" : "pause.fill")
                    .font(.caption2)
                    .frame(width: 22, height: 18)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            // Quiet at rest and orange while it holds the work back, which is
            // the state worth noticing.
            .tint(queue.isSuspended ? .orange : .secondary)
            .accessibilityLabel(queue.isSuspended ? "Resume \(kind.title)" : "Suspend \(kind.title)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(running.map { "\($0)" } ?? "unknown") of \(limit) running" + (queue.isSuspended ? ", suspended" : ""))
    }

    // MARK: Caches

    private func cachesSection(_ pipeline: DemoHUD.Pipeline, hud: DemoHUD) -> some View {
        let configuration = pipeline.configuration
        let caches = hud.caches[pipeline.id]
        let timeline = hud.timelines[pipeline.id] ?? DemoHUDTimeline()
        let urlCache = (configuration.dataLoader as? DataLoader)?.session.configuration.urlCache
        return Section {
            // A pipeline without a memory cache – the Lab turns them off – has
            // nothing to chart, and a flat line with no axis reads as broken.
            if caches?.imageCacheCostLimit ?? 0 > 0 {
                DemoMemoryCacheChart(timeline: timeline)
                    .equatable()
                    .demoFiguresRow()
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
            .demoFiguresRow()
        } header: {
            Text("Caches")
        } footer: {
            Text("What the caches of this pipeline hold. The memory figures are read with the counters; the disk ones every 3 seconds, as a `DataCache` is measured by listing its directory. A cache that two pipelines share is emptied for both. The frame pool is shared by every animation playing, whichever pipeline loaded it.")
        }
    }

    /// Empties a cache and reads the figures again, rather than leaving them
    /// as they were until the next sweep.
    private func clearing(_ action: @escaping () -> Void) -> () -> Void {
        {
            action()
            Task { await DemoHUD.shared.refreshCaches() }
        }
    }

    // MARK: App and totals

    private func appSection(_ hud: DemoHUD) -> some View {
        let fps = hud.display.framesPerSecond
        return Section {
            DemoFigureGrid(figures: [
                .init("fps", fps.map { String(format: "%.0f", $0) } ?? "–", tint: hud.display.isKeepingUp ? nil : .orange),
                .init("memory", hud.footprint.current.map { demoByteCount($0) } ?? "–"),
                .init("peak", demoByteCount(hud.footprint.peak))
            ])
            .demoFiguresRow()
            DemoHUDLines(groups: [[hud.displayLine]])
                .demoFiguresRow()
        } header: {
            Text("App")
        } footer: {
            Text("The frames of the last second, the memory the system charges the app for, and what a busy main thread cost the display, counted by a `CADisplayLink` on the main thread. It is driven at 60 Hz, on a 120 Hz display as well, so 60 fps is as high as this goes. A frame the render server drops on its own isn't seen.")
        }
    }

    private func totalSection(_ hud: DemoHUD) -> some View {
        let total = hud.total
        return Section {
            DemoFigureGrid(figures: [
                .init("active", "\(total.activeTaskCount)", tint: total.activeTaskCount > 0 ? .green : nil),
                .init("hit", DemoHUD.hitRate(total)),
                .init("done", "\(total.succeededTaskCount)")
            ])
            .demoFiguresRow()
            DemoHUDLines(groups: [DemoHUD.lines(hud.total, caches: hud.totalCaches)])
                .demoFiguresRow()
        } header: {
            Text("All Pipelines")
        } footer: {
            Text("Every pipeline added up, the ones that have gone included. A cache that two of them share counts once.")
        }
    }

    private func hudSection(_ hud: DemoHUD) -> some View {
        @Bindable var hud = hud
        return Section {
            Toggle("Show HUD", isOn: $hud.isVisible)
            Toggle("Expanded", isOn: $hud.isExpanded)
                .disabled(!hud.isVisible)
        } header: {
            Text("HUD")
        } footer: {
            Text("The HUD stands over every screen and shows the same figures for the pipeline above, folded down to what fits. The Lab section of the catalog has the same switch.")
        }
    }

    private static let info = DemoInfo(
        "Pipeline Details",
        "One pipeline: what it has done since the last reset, as the probe it is built with counts it; the last half minute of its work in charts; what runs on each of its task queues; and what its caches hold, with the controls that empty one. The HUD over every screen shows the same figures, folded down to what fits.",
        points: [
            .init("Which pipeline", "The HUD follows the pipeline that did something last, and holds on to it while it keeps busy. Pick one from the title and both sheet and HUD stay with it; the HUD shows a pin while they do."),
            .init("The charts", "The last 30 seconds, a point every half second. They are drawn in one hue, light to dark, because both stacks have an order: the stages work passes through, and how far the pipeline had to go for an image."),
            .init("Source", "Where the images came from: a download, `URLCache` and fixtures included; `DataCache`; or the memory cache, with or without a task. Hit is the share that didn't download."),
            .init("Queues", "The work running on each queue against its limit, a slot apiece. `TaskQueue` makes its limit and suspension public and keeps what waits to itself, so the probe counts what it sees running; processing it can't see at all, as processors come with the request."),
            .init("Caches", "The memory cache, the `DataCache`, the `URLCache` of the loader's session, and the shared frame pool, each against its limit. Emptying one is the way to see a screen load the same images again."),
            .init("Blind spots", "Work waiting in a queue, processing, and frames the render server drops. The disk caches are read every 3 seconds.")
        ]
    )
}

/// What the sheet is titled: the pipeline it shows, and the menu that holds it
/// to one when several are alive. In the title rather than a section of its
/// own, which a picker with one choice doesn't earn.
private struct PipelineTitle: View {
    let hud: DemoHUD

    var body: some View {
        @Bindable var hud = hud
        let label = hud.followed?.figures.label ?? "Pipeline Details"
        return Group {
            if hud.pipelines.count > 1 {
                Menu {
                    Picker("Pipeline", selection: $hud.pinnedID) {
                        Text("Active").tag(ObjectIdentifier?.none)
                        ForEach(hud.pipelines) { pipeline in
                            Text(pipeline.figures.label).tag(ObjectIdentifier?.some(pipeline.id))
                        }
                    }
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
            } else {
                Text(label)
                    .font(.headline)
            }
        }
    }
}

/// The headline figures of a pipeline, three to a row: a shape a reader scans
/// rather than a paragraph of monospaced text.
struct DemoFigureGrid: View {
    let figures: [Figure]

    struct Figure: Identifiable {
        let caption: String
        let value: String
        var tint: Color?

        var id: String { caption }

        init(_ caption: String, _ value: String, tint: Color? = nil) {
            self.caption = caption
            self.value = value
            self.tint = tint
        }
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .topLeading), count: 3),
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(figures) { figure in
                VStack(alignment: .leading, spacing: 1) {
                    Text(figure.value)
                        .font(.system(size: 17, weight: .medium, design: .monospaced))
                        .foregroundStyle(figure.tint ?? .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(figure.caption.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

extension View {
    /// A row of figures, with narrower insets than a row of controls: the
    /// charts and the monospaced blocks are set for the width they are given.
    fileprivate func demoFiguresRow() -> some View {
        listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
    }
}
