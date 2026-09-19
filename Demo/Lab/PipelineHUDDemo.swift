// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// The switch of the pipeline HUD, and every figure behind it: for the app,
/// for all the pipelines added up, and for each pipeline alive.
///
/// The HUD shows its figures over any screen, for one pipeline at a time. This
/// screen shows them for all of them at once, with the lines the HUD has no
/// room for, and says what each line counts. It samples through ``DemoHUD``,
/// as the overlay does, so the two never disagree.
struct PipelineHUDDemo: View {
    private let hud = DemoHUD.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            controls
            Section("App") {
                figures(Self.app(display: hud.display, footprint: hud.footprint))
            }
            Section("All Pipelines") {
                figures(Self.pipeline(hud.total, caches: hud.caches[.all]))
            }
            ForEach(hud.pipelines) { pipeline in
                Section(pipeline.figures.label) {
                    figures(Self.pipeline(pipeline.figures, caches: hud.caches[.pipeline(pipeline.id)]))
                }
            }
            legend
            catalog
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            hud.startSampling()
            defer { hud.stopSampling() }
            await demoWaitUntilCancelled()
        }
        .demoInfo(Self.info)
    }

    // MARK: Sections

    private var controls: some View {
        @Bindable var hud = DemoHUD.shared
        return Section {
            Toggle("Show HUD", isOn: $hud.isVisible)
            Toggle("Expanded", isOn: $hud.isExpanded)
                .disabled(!hud.isVisible)
            Button("Reset Figures") {
                hud.reset()
            }
        } footer: {
            Text("The HUD sits over every screen while it's on, and the gauge in the navigation bar of every screen switches it. Reset starts the figures of every pipeline, the display, and the peak footprint over.")
        }
    }

    /// The lines as the HUD sets them, one line each: wrapped, the padding
    /// that holds the figures still scatters them instead.
    private func figures(_ groups: [[DemoHUDLine]]) -> some View {
        DemoHUDLinesView(groups: groups)
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
    }

    private var legend: some View {
        Section("What the Lines Count") {
            ForEach(Self.legend, id: \.label) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    DemoMonoLabel(entry.label, tint: .primary)
                    Text(entry.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var catalog: some View {
        Section {
            DemoLink(.pipelineDelegate)
            DemoLink(.caching)
        } header: {
            Text("In the Catalog")
        } footer: {
            Text("The figures come from a pipeline delegate and the decorators it returns, and every demo pipeline has one.")
        }
    }

    // MARK: Figures

    /// The HUD's `footprint` and `display` lines, each with the ones it has no
    /// room for.
    private static func app(display: DemoDisplayMonitor.Figures, footprint: DemoFootprint) -> [[DemoHUDLine]] {
        typealias F = DemoHUDFigures
        let lines = F.process(display: display, footprint: footprint)
        let refresh = display.refreshInterval.map { "\(demoMilliseconds($0)) · \(Int((1 / $0).rounded())) Hz" } ?? "–"
        let hitchRatio = display.hitchTimeRatio.map { String(format: "%.1f ms/s", $0 * 1000) } ?? "–"
        return [
            [
                lines[0],
                DemoHUDLine("lifetime", "\(footprint.lifetimePeak.map { F.bytes($0) } ?? "–") peak since launch"),
                DemoHUDLine("headroom", footprint.available.map { "\(F.bytes($0)) before the limit" } ?? "– no limit here")
            ],
            [
                lines[1],
                DemoHUDLine("hitches", "\(F.count(display.hitchCount, 4, "late frame", "late frames")) · \(hitchRatio)"),
                DemoHUDLine("refresh", refresh),
                DemoHUDLine("watched", "\(demoSeconds(display.watchedDuration)) since the reset")
            ]
        ]
    }

    /// The HUD's lines for a pipeline, each group with the ones it has no room
    /// for.
    private static func pipeline(_ figures: DemoPipelineDiagnostics, caches: DemoPipelineDiagnostics.Caches?) -> [[DemoHUDLine]] {
        typealias F = DemoHUDFigures
        let failures = figures.failureCounts.isEmpty
            ? "none"
            : figures.failureCounts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: " · ")
        let formats = figures.decodingByFormat.sorted { $0.key < $1.key }.map { format, timing in
            DemoHUDLine(format, "\(F.pad(timing.count, 5)) · \(F.timing(timing.average, timing)) avg · \(F.timing(timing.max, timing)) max")
        }
        let duration = figures.taskDuration
        let previews = figures.previewDecoding
        let encoding = figures.encoding
        let ttfb = figures.timeToFirstByte
        let imageCount = caches.map { "\(F.count($0.imageCacheCount, 5, "image", "images")) in memory" } ?? "…"
        return [
            F.tasks(figures) + [
                DemoHUDLine("created", "\(F.pad(figures.createdTaskCount, 5)) · \(F.pad(figures.peakActiveTaskCount, 4)) active at most"),
                DemoHUDLine("duration", "\(F.timing(duration.average, duration, width: 8)) avg · \(F.timing(duration.max, duration, width: 8)) max"),
                DemoHUDLine("failures", failures)
            ],
            F.work(figures) + [
                DemoHUDLine("decoded", "\(F.count(figures.decoding.count, 5, "image", "images")) · \(F.pad(figures.failedDecodeCount, 3)) failed"),
                DemoHUDLine("previews", "\(F.pad(previews.count, 5)) · \(F.timing(previews.average, previews)) avg · \(F.timing(previews.max, previews)) max")
            ] + formats + [
                DemoHUDLine("encode", "\(F.pad(encoding.count, 5)) · \(F.timing(encoding.average, encoding)) avg · queue \(figures.encodingQueue.inFlightCount.map { "\($0)" } ?? "–")/\(figures.encodingQueue.limit)")
            ],
            F.network(figures) + [
                DemoHUDLine("downloads", "\(F.pad(figures.downloadCount, 5)) started · \(F.pad(figures.completedDownloadCount, 5)) completed"),
                DemoHUDLine(
                    "unfinished",
                    .init("\(F.pad(figures.cancelledDownloadCount, 5)) cancelled · \(F.pad(figures.failedDownloadCount, 3)) failed · "),
                    .init("\(F.pad(figures.cancelledInFlightDownloadCount, 2)) stuck", tint: figures.cancelledInFlightDownloadCount > 0 ? .orange : nil)
                ),
                DemoHUDLine("ttfb", "\(F.timing(ttfb.last, ttfb)) · \(F.timing(ttfb.average, ttfb)) avg · \(F.timing(ttfb.max, ttfb)) max"),
                DemoHUDLine("reused", "\(F.count(figures.reusedConnectionCount, 5, "download", "downloads")) on an open connection"),
                DemoHUDLine("urlcache", "\(F.pad(figures.httpCacheLoadCount, 5)) answered · \(F.bytes(figures.httpCacheByteCount))"),
                DemoHUDLine("fixtures", "\(F.pad(figures.fixtureLoadCount, 5)) served · \(F.bytes(figures.fixtureByteCount))")
            ],
            F.storage(caches) + [
                DemoHUDLine("images", imageCount),
                DemoHUDLine("mem reads", "\(F.pad(figures.memoryCacheHitCount, 5)) hits of \(F.pad(figures.memoryCacheLookupCount, 5)) · \(F.pad(figures.memoryHitWithoutTaskCount, 5)) no task"),
                DemoHUDLine("disk reads", "\(F.pad(figures.diskCacheHitCount, 5)) hits of \(F.pad(figures.diskCacheLookupCount, 5)) · \(F.bytes(figures.diskCacheHitByteCount))"),
                DemoHUDLine("disk write", "\(F.pad(figures.diskWriteCount, 5)) · \(F.bytes(figures.diskWriteByteCount)) · \(F.pad(figures.encodedImageWriteCount, 3)) encoded")
            ]
        ]
    }

    /// One entry for every label, in the order the tables show them.
    private static let legend: [(label: String, text: LocalizedStringKey)] = [
        ("footprint", "`phys_footprint` from `task_vm_info`, the memory the system charges the app for, and the highest of it sampled since the reset."),
        ("lifetime", "`ledger_phys_footprint_peak`, the kernel's own peak since launch, which misses no spike and can't be reset."),
        ("headroom", "`os_proc_available_memory()`, what the app can take before the system terminates it. The simulator sets no limit."),
        ("display", "Frames in the last second, the refreshes the main thread missed, and the longest wait between two frames, counted while the HUD or this screen is open. A frame the render server drops on its own isn't seen, and the HUD's own drawing is counted."),
        ("hitches", "Frames that arrived late, however many refreshes each one cost, and how late they were per second watched."),
        ("refresh", "The interval the display link is driven at, which late frames are measured against."),
        ("watched", "How long the display has been watched since the reset."),
        ("tasks", "Image tasks running, and the ones that ended with an image, cancelled, or with an error. Data tasks and NukeUI's memory cache hits create none."),
        ("coalescing", "Images that came from a download against the downloads that brought them. Above 1×, tasks shared downloads."),
        ("source", "Where the images came from: a download, `URLCache` included; `DataCache`; or the memory cache, with or without a task. Hit is the share that didn't download. The download count reads `fixture` when fixtures answered every download, and `fetched` when they answered some: the probe counts fixtures by download, so a mix can't be split by image."),
        ("created", "Image tasks created, and the most running at once."),
        ("duration", "From creating a task to its image, for the tasks that succeeded."),
        ("failures", "Failed tasks by `ImagePipeline.Error` case."),
        ("queues", "Work running on each queue, as the probe sees it, against the queue's limit; orange while a queue is suspended. A dash is work the probe can't see, and work waiting is never seen. A synchronous decode doesn't run on the decoding queue."),
        ("decode", "The last, average, and slowest final decode."),
        ("decompress", "The average and slowest `decompress`. Declined counts `shouldDecompress` saying no; a thumbnail, a processed image, and `.skipDecompression` are skipped before it is asked."),
        ("decoded", "Final decodes that produced an image, and the ones that threw."),
        ("previews", "Partial decodes that produced a progressive preview."),
        ("jpeg, png, …", "Final decodes by the format of the image."),
        ("encode", "Encodes of a processed image for the disk cache, and the encoding queue."),
        ("network", "Bytes of the downloads that ended and of the ones in flight, and the average time to the first byte. Fixtures are left out, except from the bytes in flight."),
        ("saved", "Bytes read from `DataCache` or answered by `URLCache`, then the bytes fixtures delivered. A memory cache hit saves a download too, of a size nobody knows."),
        ("downloads", "`dataLoader(for:)` calls, one per download after coalescing, and the downloads that completed."),
        ("unfinished", "Downloads cancelled and failed. Stuck ones were cancelled and their loader never called `completion`, which holds a data loading slot for good."),
        ("ttfb", "From the start of a download to its first chunk, for the downloads neither `URLCache` nor a fixture answered."),
        ("reused", "Downloads that went over a connection an earlier one opened. Known only for a `DataLoader`."),
        ("urlcache", "Downloads `URLCache` answered without a request, and their bytes."),
        ("fixtures", "Downloads a fixture loader completed in place of a request, and the bytes fixtures delivered."),
        ("memory", "Decoded images in the image caches and frames in `AnimatedImageFramePool`, against their limits; read every 3 seconds. Caches that pipelines share count once, and the limits of the others add up."),
        ("disk", "What `DataCache` and the `URLCache` of the pipelines' `DataLoader`s hold, read off the disk every 3 seconds. A write to `DataCache` counts after about a second in staging."),
        ("images", "The images in the image caches."),
        ("mem reads", "Memory cache reads and their hits; no task counts the hits NukeUI makes on the main thread before it starts a task."),
        ("disk reads", "`DataCache` reads, their hits, and the bytes those returned."),
        ("disk write", "Writes `willCache` let through, their bytes, and the ones that stored an encoded image.")
    ]

    private static let info = DemoInfo(
        "Pipeline HUD",
        "What every pipeline in the demo has done since the last reset, as the probe each one is built with counts it, and what the app's memory and the display are doing. The HUD shows the same figures over any screen, for one pipeline at a time.",
        points: [
            .init("Switching it on", "The gauge in the navigation bar of every screen, the switch at the top of this screen, or `-demoHUD 1` at launch – `-demoHUD expanded` opens the panel. The pill opens the panel; drag either to the other side."),
            .init("Which pipeline", "Automatic follows the pipeline that did something last, and holds on to it while it keeps busy. The menu at the top of the panel picks one, or all of them added up."),
            .init("Room", "While the HUD is on, every screen leaves a strip at the bottom for the pill, and the HUD rises above a console that is a sheet. The panel covers what is under it; fold it to see the screen."),
            .init("Blind spots", "Work waiting in a queue, processing, what a memory cache hit saved, and frames the render server drops. A figure nothing measured is a dash."),
            .init("Cost", "A lock and a copy per pipeline ten times a second, a directory listing every 3 seconds, and a display link, all while the HUD or this screen is open. Hidden, the HUD runs nothing.")
        ]
    )
}
