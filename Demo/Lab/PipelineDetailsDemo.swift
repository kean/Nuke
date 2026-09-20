// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import SwiftUI

/// One pipeline at a time: what it has done, what runs on each of its task
/// queues, what its caches hold, and the controls that empty a cache or
/// suspend a queue. The switches of the HUD are at the end.
///
/// It shows the pipeline the HUD shows, and its picker holds the HUD to one
/// when several are alive – see ``DemoHUD/pinnedID``.
///
/// Opened from the HUD's menu: the catalog has no row for it.
struct PipelineDetailsDemo: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let hud = DemoHUD.shared
        List {
            picker(hud)
            if let pipeline = hud.followed {
                figuresSection(pipeline, hud: hud)
                queuesSection(pipeline)
                cachesSection(pipeline, hud: hud)
            }
            Section("App") {
                stats(hud.appStats)
                lines(hud.appLines)
            }
            Section("All Pipelines") {
                stats(DemoHUD.stats(hud.total))
                lines(DemoHUD.lines(hud.total, caches: hud.totalCaches))
            }
            hudSection(hud)
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await hud.sampleUntilCancelled()
        }
        .demoInfo(Self.info)
    }

    // MARK: Pipeline

    /// Which pipeline the screen – and the HUD with it – shows. With one
    /// pipeline alive there is nothing to pick, so it says which one it is.
    @ViewBuilder
    private func picker(_ hud: DemoHUD) -> some View {
        @Bindable var hud = hud
        Section {
            if hud.pipelines.count > 1 {
                Picker("Pipeline", selection: $hud.pinnedID) {
                    Text("Active").tag(ObjectIdentifier?.none)
                    ForEach(hud.pipelines) { pipeline in
                        Text(pipeline.figures.label).tag(ObjectIdentifier?.some(pipeline.id))
                    }
                }
            } else {
                LabeledContent("Pipeline", value: hud.followed?.figures.label ?? "None")
            }
        } footer: {
            Text("The HUD follows the pipeline that did something last. Pick one and both it and the HUD hold to it, until Active or until that pipeline goes away.")
        }
    }

    private func figuresSection(_ pipeline: DemoHUD.Pipeline, hud: DemoHUD) -> some View {
        Section {
            stats(DemoHUD.stats(pipeline.figures))
            lines(DemoHUD.lines(pipeline.figures, caches: hud.caches[pipeline.id]))
        } header: {
            Text("Figures")
        } footer: {
            Text("What this pipeline has done since the last reset, as the probe it is built with counts it. Hit is the share of the images that didn't download.")
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

    private func queuesSection(_ pipeline: DemoHUD.Pipeline) -> some View {
        Section {
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
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title)
                    .font(.subheadline)
                HStack(spacing: 8) {
                    if let running {
                        slots(running: running, limit: limit, isSuspended: queue.isSuspended)
                    }
                    DemoMonoLabel("\(running.map { "\($0)" } ?? "–")/\(limit) running" + (queue.isSuspended ? " · suspended" : ""), tint: queue.isSuspended ? .orange : .primary)
                }
            }
            Spacer(minLength: 0)
            Button(queue.isSuspended ? "Resume" : "Suspend") {
                queue.isSuspended.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    /// A square per slot, filled while work runs in it.
    private func slots(running: Int, limit: Int, isSuspended: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<limit, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < running ? (isSuspended ? Color.orange : .accentColor) : Color.primary.opacity(0.12))
                    .frame(width: 7, height: 10)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Caches

    private func cachesSection(_ pipeline: DemoHUD.Pipeline, hud: DemoHUD) -> some View {
        let configuration = pipeline.configuration
        let urlCache = (configuration.dataLoader as? DataLoader)?.session.configuration.urlCache
        return Section {
            lines(Self.cacheLines(hud.caches[pipeline.id]))
            clearButton("Clear Memory Cache") {
                configuration.imageCache?.removeAll()
            }
            .disabled(configuration.imageCache == nil)
            clearButton("Clear Disk Cache") {
                configuration.dataCache?.removeAll()
            }
            .disabled(configuration.dataCache == nil)
            clearButton("Clear HTTP Cache") {
                urlCache?.removeAllCachedResponses()
            }
            .disabled(urlCache == nil)
        } header: {
            Text("Caches")
        } footer: {
            Text("What the caches of this pipeline hold, read every 3 seconds: a `DataCache` is measured by listing its directory. A cache that two pipelines share is emptied for both. The frame pool is shared by every animation playing, whichever pipeline loaded it.")
        }
    }

    private static func cacheLines(_ caches: DemoPipelineDiagnostics.Caches?) -> [DemoHUD.Line] {
        guard let caches else {
            return [DemoHUD.Line(label: "caches", value: "…")]
        }
        return [
            DemoHUD.Line(label: "memory", value: "\(bytes(caches.imageCacheCost, of: caches.imageCacheCostLimit)) · \(demoCount(caches.imageCacheCount, "image"))"),
            DemoHUD.Line(label: "disk", value: caches.dataCacheSize.map {
                "\(bytes($0, of: caches.dataCacheSizeLimit ?? 0)) · \(demoCount(caches.dataCacheCount ?? 0, "file"))"
            } ?? "none"),
            DemoHUD.Line(label: "http", value: caches.urlCacheDiskUsage.map {
                bytes($0, of: caches.urlCacheDiskCapacity ?? 0)
            } ?? "none"),
            DemoHUD.Line(label: "pool", value: bytes(caches.framePoolCost, of: caches.framePoolCostLimit))
        ]
    }

    private static func bytes(_ count: Int, of limit: Int) -> String {
        limit > 0 ? "\(demoByteCount(count))/\(demoByteCount(limit))" : demoByteCount(count)
    }

    /// Empties a cache and reads the figures again, rather than leaving them
    /// as they were until the next sweep.
    private func clearButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            action()
            Task { await DemoHUD.shared.refreshCaches() }
        }
    }

    // MARK: HUD

    private func hudSection(_ hud: DemoHUD) -> some View {
        @Bindable var hud = hud
        return Section {
            Toggle("Show HUD", isOn: $hud.isVisible)
            Toggle("Expanded", isOn: $hud.isExpanded)
                .disabled(!hud.isVisible)
            Button("Reset Figures") {
                hud.reset()
            }
        } header: {
            Text("HUD")
        } footer: {
            Text("The HUD stands over every screen and shows the same figures for the pipeline above. The Lab section of the catalog has the same switch.")
        }
    }

    // MARK: Rows

    private func stats(_ stats: [DemoHUD.Stat]) -> some View {
        row {
            DemoHUDStats(stats: stats)
                .frame(maxWidth: 280, alignment: .leading)
        }
    }

    private func lines(_ lines: [DemoHUD.Line]) -> some View {
        row {
            DemoHUDLines(groups: [lines])
        }
    }

    /// With narrow insets, as the figures are set for the width of the HUD.
    private func row(@ViewBuilder content: () -> some View) -> some View {
        content()
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
    }

    private static let info = DemoInfo(
        "Pipeline Details",
        "One pipeline: what it has done since the last reset, as the probe it is built with counts it; what runs on each of its task queues; and what its caches hold, with the controls that empty one. The HUD over every screen shows the same figures, folded down to what fits.",
        points: [
            .init("Which pipeline", "The HUD follows the pipeline that did something last, and holds on to it while it keeps busy. Pick one at the top and both screen and HUD stay with it; the HUD's header shows a pin while they do."),
            .init("Source", "Where the images came from: a download, `URLCache` and fixtures included; `DataCache`; or the memory cache, with or without a task. Hit is the share that didn't download."),
            .init("Queues", "The work running on each queue against its limit, a slot apiece. `TaskQueue` makes its limit and suspension public and keeps what waits to itself, so the probe counts what it sees running; processing it can't see at all, as processors come with the request."),
            .init("Caches", "The memory cache, the `DataCache`, the `URLCache` of the loader's session, and the shared frame pool, each against its limit. Emptying one is the way to see a screen load the same images again."),
            .init("Blind spots", "Work waiting in a queue, processing, and frames the render server drops. The caches are read every 3 seconds.")
        ]
    )
}
