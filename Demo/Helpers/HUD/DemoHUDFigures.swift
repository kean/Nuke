// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// A line of the pipeline HUD: a label and the figures after it, each run of
/// them in its color.
struct DemoHUDLine: Identifiable {
    let label: String
    let runs: [Run]

    var id: String { label }

    init(_ label: String, _ runs: Run...) {
        self.label = label
        self.runs = runs
    }

    init(_ label: String, _ text: String) {
        self.init(label, Run(text))
    }

    /// The figures after the label.
    var text: Text {
        runs.reduce(Text(verbatim: "")) { text, run in
            text + Text(verbatim: run.text).foregroundStyle(run.tint ?? .primary)
        }
    }

    /// A piece of a line in one color.
    struct Run {
        let text: String
        let tint: Color?

        init(_ text: String, tint: Color? = nil) {
            self.text = text
            self.tint = tint
        }
    }

    /// The characters the label column takes, the space after it included.
    static let labelWidth = 11
    /// The characters a line is laid out for, label included. The figures of
    /// every line fit in it at the counts a busy screen reaches; a line that
    /// runs longer shrinks rather than wraps.
    static let columns = labelWidth + 50
}

/// The lines of the pipeline HUD, written once for the overlay and for the
/// **Pipeline HUD** screen in the Lab.
///
/// The overlay shows them in four groups: what the tasks did and where their
/// images came from; the queues and the time spent decoding; the network; and
/// the caches, the app's memory, and the display. A figure that swings is
/// padded to the width it reaches in a busy run, so that a line sampled ten
/// times a second keeps its words where they are. A figure nothing measured is
/// a dash, never a zero.
enum DemoHUDFigures {
    /// Every line of the overlay, in groups.
    static func groups(
        _ figures: DemoPipelineDiagnostics,
        caches: DemoPipelineDiagnostics.Caches?,
        display: DemoDisplayMonitor.Figures,
        footprint: DemoFootprint
    ) -> [[DemoHUDLine]] {
        [
            tasks(figures),
            work(figures),
            network(figures),
            storage(caches) + process(display: display, footprint: footprint)
        ]
    }

    /// `tasks`, `coalescing`, `source`.
    static func tasks(_ figures: DemoPipelineDiagnostics) -> [DemoHUDLine] {
        let ratio = figures.completedDownloadCount > 0 ? String(format: "%.1f×", figures.coalescingRatio) : "–"
        return [
            DemoHUDLine("tasks", "\(pad(figures.activeTaskCount, 3)) active · \(pad(figures.succeededTaskCount, 4)) done · \(pad(figures.cancelledTaskCount, 3)) cancelled · \(pad(figures.failedTaskCount, 2)) failed"),
            // Images from the network against the downloads that brought
            // them: tasks served from a cache would read as coalescing.
            DemoHUDLine(
                "coalescing",
                .init("\(count(figures.networkResponseCount, 4, "image", "images")) → \(count(figures.completedDownloadCount, 4, "download", "downloads")) · "),
                .init(ratio, tint: figures.coalescingRatio >= 1.05 ? .green : nil)
            ),
            DemoHUDLine(
                "source",
                .init("\(pad(figures.networkResponseCount, 4)) network · \(pad(figures.diskResponseCount, 4)) disk · \(pad(figures.servedFromMemoryCount, 4)) memory · "),
                .init("\(demoPad(hitRate(figures), to: 4)) hit", tint: figures.hitRate > 0 ? .green : nil)
            )
        ]
    }

    /// `queues`, `decode`, `decompress`.
    static func work(_ figures: DemoPipelineDiagnostics) -> [DemoHUDLine] {
        let decoding = figures.decoding
        let decompression = figures.decompression
        return [
            DemoHUDLine(
                "queues",
                queue("load", figures.dataLoadingQueue, isLast: false),
                queue("decode", figures.decodingQueue, isLast: false),
                queue("process", figures.processingQueue, isLast: false),
                queue("decomp", figures.decompressingQueue, isLast: true)
            ),
            DemoHUDLine("decode", "\(timing(decoding.last, decoding)) · \(timing(decoding.average, decoding)) avg · \(timing(decoding.max, decoding)) max"),
            DemoHUDLine("decompress", "\(timing(decompression.average, decompression)) avg · \(timing(decompression.max, decompression)) max · \(pad(figures.declinedDecompressionCount, 3)) declined")
        ]
    }

    /// `network`, `saved`. Offline, the network line stays at zero and the
    /// bytes are the fixtures'.
    static func network(_ figures: DemoPipelineDiagnostics) -> [DemoHUDLine] {
        let timeToFirstByte = figures.timeToFirstByte.count > 0 ? demoDelay(figures.timeToFirstByte.average) : "–"
        return [
            DemoHUDLine("network", "\(bytes(figures.downloadedByteCount)) down · \(bytes(figures.inFlightByteCount)) in flight · \(demoPad(timeToFirstByte, to: 5)) ttfb"),
            DemoHUDLine("saved", "\(bytes(figures.savedByteCount)) not re-downloaded · \(bytes(figures.fixtureByteCount)) fixtures")
        ]
    }

    /// `memory`, `disk`: an ellipsis until the caches have been sampled once,
    /// which takes a trip off the main thread.
    static func storage(_ caches: DemoPipelineDiagnostics.Caches?) -> [DemoHUDLine] {
        guard let caches else {
            return [DemoHUDLine("memory", "…"), DemoHUDLine("disk", "…")]
        }
        let image = caches.imageCacheCostLimit > 0
            ? "\(bytes(caches.imageCacheCost, width: 7))/\(demoByteCount(caches.imageCacheCostLimit))"
            : "none"
        let pool = "\(bytes(caches.framePoolCost, width: 7))/\(demoByteCount(caches.framePoolCostLimit))"
        let data = caches.dataCacheSize.map { size in
            "data \(bytes(size, width: 7))/\(demoByteCount(caches.dataCacheSizeLimit ?? 0))"
        }
        let http = caches.urlCacheDiskUsage.map { usage in
            "http \(bytes(usage, width: 7))/\(demoByteCount(caches.urlCacheDiskCapacity ?? 0))"
        }
        let disk = switch (data, http) {
        case let (data?, http?): "\(data) · \(http)"
        case let (data?, nil): "\(data) · \(count(caches.dataCacheCount ?? 0, 4, "file", "files"))"
        case let (nil, http?): http
        case (nil, nil): "no disk cache"
        }
        return [
            DemoHUDLine("memory", "image \(image) · pool \(pool)"),
            DemoHUDLine("disk", disk)
        ]
    }

    /// `footprint`, `display`.
    static func process(display: DemoDisplayMonitor.Figures, footprint: DemoFootprint) -> [DemoHUDLine] {
        let current = footprint.current.map { bytes($0) } ?? demoPad("–", to: 8)
        let fps = display.framesPerSecond.map { String(format: "%.1f", $0) } ?? "–"
        let worst = display.watchedDuration > 0 ? demoDelay(display.longestFrame) : "–"
        return [
            DemoHUDLine("footprint", "\(current) · peak \(bytes(footprint.peak))"),
            DemoHUDLine(
                "display",
                .init("\(demoPad(fps, to: 5)) fps · "),
                .init(
                    "\(count(display.droppedFrameCount, 4, "frame", "frames")) dropped · \(demoPad(worst, to: 5)) worst",
                    tint: display.droppedFrameCount > 0 ? .orange : nil
                )
            )
        ]
    }

    /// The figures of the folded HUD: whether anything is loading, whether
    /// the caches are answering, and whether the screen keeps up.
    static func headline(_ figures: DemoPipelineDiagnostics, display: DemoDisplayMonitor.Figures) -> String {
        let fps = display.framesPerSecond.map { String(format: "%.0f", $0) } ?? "–"
        return "\(pad(figures.activeTaskCount, 3)) active · \(demoPad(hitRate(figures), to: 4)) hit · \(demoPad(fps, to: 3)) fps"
    }

    // MARK: Formatting

    static func pad(_ value: Int, _ width: Int) -> String {
        demoPad("\(value)", to: width)
    }

    /// A count and its noun, the singular padded to the plural's length so
    /// that the words after it hold still: `   1 image `.
    static func count(_ value: Int, _ width: Int, _ singular: String, _ plural: String) -> String {
        let noun = value == 1 ? singular.padding(toLength: plural.count, withPad: " ", startingAt: 0) : plural
        return "\(pad(value, width)) \(noun)"
    }

    /// A byte count, padded by default to the width of "184.2 MB".
    static func bytes(_ count: Int, width: Int = 8) -> String {
        demoPad(demoByteCount(count), to: width)
    }

    static func bytes(_ count: Int64, width: Int = 8) -> String {
        demoPad(demoByteCount(count), to: width)
    }

    /// A time from `timing` in milliseconds, or a dash if it timed nothing.
    static func timing(_ value: TimeInterval, _ timing: DemoPipelineDiagnostics.Timing, width: Int = 6) -> String {
        demoPad(timing.count > 0 ? demoMilliseconds(value) : "–", to: width)
    }

    /// The share of images that didn't need a download, or a dash before the
    /// first one.
    static func hitRate(_ figures: DemoPipelineDiagnostics) -> String {
        let count = figures.networkResponseCount + figures.diskResponseCount + figures.servedFromMemoryCount
        return count > 0 ? "\(Int((figures.hitRate * 100).rounded()))%" : "–"
    }

    /// `load 6/6 · `: the work running against the limit, orange while the
    /// queue is suspended, which starts nothing whatever its count says.
    private static func queue(_ name: String, _ queue: DemoPipelineDiagnostics.Queue, isLast: Bool) -> DemoHUDLine.Run {
        let limit = "\(queue.limit)"
        let count = queue.inFlightCount.map { "\($0)" } ?? "–"
        let text = "\(name) \(demoPad(count, to: limit.count))/\(limit)" + (isLast ? "" : " · ")
        return DemoHUDLine.Run(text, tint: queue.isSuspended ? .orange : nil)
    }
}

/// Lines of figures in one monospaced block, sized so that
/// ``DemoHUDLine/columns`` characters fill the width it is given: every line
/// the same size, and a size that doesn't change as the figures do.
struct DemoHUDLinesView: View {
    let groups: [[DemoHUDLine]]
    var maxFontSize: CGFloat = 12

    @State private var width: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(groups.indices, id: \.self) { index in
                if index > 0 {
                    Divider()
                }
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(groups[index]) { line in
                        text(for: line)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .font(.system(size: fontSize, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// In half points. A character of SF Mono is 0.6 of the point size wide;
    /// the rest is slack.
    private var fontSize: CGFloat {
        guard width > 0 else { return 9 }
        let size = width / (CGFloat(DemoHUDLine.columns) * 0.6 * 1.02)
        return min(maxFontSize, (size * 2).rounded(.down) / 2)
    }

    private func text(for line: DemoHUDLine) -> Text {
        let label = line.label.padding(toLength: DemoHUDLine.labelWidth, withPad: " ", startingAt: 0)
        return Text(verbatim: label).foregroundStyle(.secondary) + line.text
    }
}
