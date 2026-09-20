// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// The last half minute of one pipeline's life, as the HUD samples it: what
/// the charts on the **Pipeline Details** sheet are drawn from.
///
/// The HUD reads the counters ten times a second and records a point every
/// fifth one, so a chart redraws twice a second rather than ten times, and
/// half a minute is 60 points rather than 300. Half a minute rather than a
/// whole one because the bars have to be wide enough to see: 60 of them across
/// a phone is a few points each, and 120 is a hairline.
///
/// The probe's counters only ever grow, so a point keeps the difference from
/// the point before it – the images that finished in that half second, the
/// bytes that arrived in it. What is true at an instant rather than counted
/// over one – the work in flight, what the memory cache holds – is stored as
/// it was read.
struct DemoHUDTimeline: Equatable {
    /// The points, oldest last-but-one, at most ``capacity`` of them.
    private(set) var points: [Point] = []

    /// What the counters stood at when the last point was taken, which the
    /// next point's differences are measured from.
    private var previous: Totals?
    /// The id of the next point. It only ever grows, so the charts can slide
    /// their x axis along rather than redraw the window from the left.
    private var nextID = 0

    /// How long one point covers.
    static let interval: TimeInterval = 0.5
    /// The points half a minute holds.
    static let capacity = 60

    /// The window the charts draw, which is the whole half minute from the
    /// first point on: a chart that grew with its data would squeeze the first
    /// seconds of a run into the full width and then slide, which reads as two
    /// different charts.
    var domain: ClosedRange<Int> {
        let end = Swift.max(nextID, Self.capacity)
        return (end - Self.capacity)...end
    }

    /// Whether anything has been recorded since the last reset.
    var isEmpty: Bool { points.isEmpty }

    /// Records where the pipeline stands now. Called on the HUD's sampling
    /// tick, once every ``interval``.
    mutating func record(_ figures: DemoPipelineDiagnostics, imageCacheCost: Int) {
        let totals = Totals(figures)
        defer { previous = totals }
        // The first call sets the baseline the next one is measured from: a
        // pipeline that had already loaded a hundred images doesn't open its
        // chart with a hundred-image spike.
        guard let previous else { return }

        var point = Point(id: nextID)
        nextID += 1
        point.activeTaskCount = figures.activeTaskCount
        point.loadingCount = figures.dataLoadingQueue.inFlightCount ?? 0
        point.decodingCount = figures.decodingQueue.inFlightCount ?? 0
        point.decompressingCount = figures.decompressingQueue.inFlightCount ?? 0
        point.memoryCount = totals.memory - previous.memory
        point.diskCount = totals.disk - previous.disk
        point.networkCount = totals.network - previous.network
        point.downloadedByteCount = Swift.max(0, totals.downloadedBytes - previous.downloadedBytes)
        point.imageCacheCost = imageCacheCost

        points.append(point)
        if points.count > Self.capacity {
            points.removeFirst(points.count - Self.capacity)
        }
    }

    /// Empties the window. The next point sets a new baseline rather than
    /// counting everything since the last one as having happened at once.
    mutating func reset() {
        points.removeAll(keepingCapacity: true)
        previous = nil
    }

    /// The counters a point's differences are taken from.
    private struct Totals: Equatable {
        let memory: Int
        let disk: Int
        let network: Int
        let downloadedBytes: Int64

        init(_ figures: DemoPipelineDiagnostics) {
            memory = figures.servedFromMemoryCount
            disk = figures.diskResponseCount
            network = figures.networkResponseCount
            downloadedBytes = figures.downloadedByteCount
        }
    }
}

extension DemoHUDTimeline {
    /// Half a second of a pipeline's life.
    struct Point: Identifiable, Sendable, Equatable {
        let id: Int

        /// The tasks that had not finished, at the instant the point was taken.
        var activeTaskCount = 0

        /// The work running on each queue at that instant.
        var loadingCount = 0
        var decodingCount = 0
        var decompressingCount = 0

        /// The images that finished in this half second, by where they came
        /// from.
        var memoryCount = 0
        var diskCount = 0
        var networkCount = 0

        /// The response bytes that arrived in this half second.
        var downloadedByteCount: Int64 = 0
        /// What the memory cache held at the instant, in bytes.
        var imageCacheCost = 0
    }

    /// The task queues the probe can see, in the order work passes through
    /// them. The charts draw them as a ramp in that order, so the stack reads
    /// from the front of the pipeline at the bottom to the back of it at the
    /// top.
    enum Stage: String, CaseIterable, Identifiable {
        case loading = "Loading"
        case decoding = "Decoding"
        case decompressing = "Decompressing"

        var id: String { rawValue }

        var count: KeyPath<Point, Int> {
            switch self {
            case .loading: \.loadingCount
            case .decoding: \.decodingCount
            case .decompressing: \.decompressingCount
            }
        }
    }

    /// Where an image came from, cheapest first. The charts draw them as a
    /// ramp in that order: the darker the stack, the further the pipeline had
    /// to go for the images.
    enum Source: String, CaseIterable, Identifiable {
        case memory = "Memory"
        case disk = "Disk"
        case network = "Network"

        var id: String { rawValue }

        var count: KeyPath<Point, Int> {
            switch self {
            case .memory: \.memoryCount
            case .disk: \.diskCount
            case .network: \.networkCount
            }
        }
    }

    /// The work running on the queues, as one row per point and queue: the
    /// shape a chart plots.
    var stageRows: [Row] {
        points.flatMap { point in
            Stage.allCases.map { Row(point: point, series: $0.rawValue, keyPath: $0.count) }
        }
    }

    /// The images that finished, as one row per point and source.
    var sourceRows: [Row] {
        points.flatMap { point in
            Source.allCases.map { Row(point: point, series: $0.rawValue, keyPath: $0.count) }
        }
    }

    /// One point of one series.
    struct Row: Identifiable {
        let point: Int
        let series: String
        let value: Int

        var id: String { "\(point)-\(series)" }

        init(point: Point, series: String, keyPath: KeyPath<Point, Int>) {
            self.point = point.id
            self.series = series
            self.value = point[keyPath: keyPath]
        }
    }
}
