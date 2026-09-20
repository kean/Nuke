// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Charts
import SwiftUI

/// The ramp every chart on the **Pipeline Details** sheet is drawn in: one
/// hue, light to dark.
///
/// Both of the stacks the sheet draws are ordered rather than merely
/// different – the stages work passes through, and where an image came from,
/// which costs more the further down the list it is – so they take a ramp
/// rather than a set of hues, and the reader gets the order for free: the
/// darker the stack, the further along, or the further away, the work was.
///
/// It also leaves orange alone. Orange means trouble everywhere else in the
/// demo – a suspended queue, a dropped frame, a failed task – and a chart that
/// spent it on "the decoding queue" would take that away.
///
/// Three steps of the blue ramp, picked for the surface they sit on rather
/// than one appearance dimmed for the other, and checked in both: each step is
/// a visible distance in lightness from the next, and the lightest still reads
/// against the row behind it.
enum DemoChartRamp {
    /// Lightest first.
    static let steps: [Color] = [
        Color(lightHex: 0x86B6EF, darkHex: 0x9EC5F4),
        Color(lightHex: 0x2A78D6, darkHex: 0x3987E5),
        Color(lightHex: 0x104281, darkHex: 0x184F95)
    ]

    /// The one color a chart of a single series is drawn in.
    static var single: Color { steps[1] }

    /// The ramp as a chart's style scale: the series in their own order, so a
    /// series keeps its step whether or not the others have any values.
    static func scale(_ series: [String]) -> KeyValuePairs<String, Color> {
        // `chartForegroundStyleScale` takes the pairs literally, and a
        // `KeyValuePairs` can't be built from an array, so the three sizes the
        // sheet uses are written out.
        switch series.count {
        case 2: [series[0]: steps[0], series[1]: steps[2]]
        case 3: [series[0]: steps[0], series[1]: steps[1], series[2]: steps[2]]
        default: [:]
        }
    }
}

/// A chart of the last half minute, drawn small: a title, the chart, and the legend
/// under it. Every chart on the sheet is built from this one, so they line up
/// and read as a set.
struct DemoTimelineChart<Content: ChartContent>: View {
    let title: String
    let caption: String
    /// The series in the order they stack, bottom first. One series needs no
    /// legend – the title names it – so it passes none.
    var series: [String] = []
    /// The window, which is the whole half minute whatever has been recorded
    /// so far.
    let domain: ClosedRange<Int>
    /// The top of the y axis, or `nil` to let the chart find it. A live chart
    /// that rescales on every point is hard to read, so the ones that have a
    /// ceiling – a queue can't run more work than its limit – pass it.
    var yMaximum: Int?
    /// How a value is written on the y axis, for an axis that isn't a count.
    var yLabel: ((Double) -> String)?
    var height: CGFloat = 84
    var isEmpty = false
    @ChartContentBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            chart
                .frame(height: height)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var chart: some View {
        if isEmpty {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay {
                    Text("Nothing yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        } else {
            Chart(content: content)
                .chartXScale(domain: domain)
                .chartXAxis(.hidden)
                .modifier(DemoChartYScale(maximum: yMaximum))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        // Solid hairlines a shade off the surface: a dashed
                        // grid reads as a threshold, which none of these are.
                        AxisGridLine()
                            .foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel {
                            Text(label(for: value))
                        }
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                    }
                }
                .modifier(DemoChartSeriesStyle(series: series))
        }
    }

    private func label(for value: AxisValue) -> String {
        let number = value.as(Double.self) ?? 0
        return yLabel?(number) ?? "\(Int(number))"
    }
}

/// Holds the y axis to a ceiling where there is one. A live chart that
/// rescales as its tallest point comes and goes is hard to read.
private struct DemoChartYScale: ViewModifier {
    let maximum: Int?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let maximum {
            content.chartYScale(domain: 0...Double(max(1, maximum)))
        } else {
            content
        }
    }
}

/// Pins the series to their steps of the ramp and puts the legend under the
/// chart. A chart of one series takes neither: its title names what it draws.
private struct DemoChartSeriesStyle: ViewModifier {
    let series: [String]

    func body(content: Content) -> some View {
        if series.count > 1 {
            content
                .chartForegroundStyleScale(DemoChartRamp.scale(series))
                .chartLegend(position: .bottom, alignment: .leading, spacing: 6)
        } else {
            content.chartLegend(.hidden)
        }
    }
}

/// The images a pipeline finished, stacked by where they came from.
///
/// Equatable, and asked for as such at the call site: the sheet around it is
/// rebuilt ten times a second with the rest of the figures, while a timeline
/// gains a point twice a second, and redrawing a few hundred marks for nothing
/// is not what an instrument should cost.
struct DemoRequestsChart: View, Equatable {
    let timeline: DemoHUDTimeline

    var body: some View {
        let busiest = timeline.points.map { $0.memoryCount + $0.diskCount + $0.networkCount }.max() ?? 0
        DemoTimelineChart(
            title: "Images finished",
            caption: "One bar every half second, over the last 30 seconds",
            series: DemoHUDTimeline.Source.allCases.map(\.rawValue),
            domain: timeline.domain,
            // Idle, there are no bars for the chart to scale to, and a box
            // without an axis reads as broken rather than quiet.
            yMaximum: busiest > 0 ? nil : 4,
            height: 92,
            isEmpty: timeline.isEmpty
        ) {
            // A bar of nothing is still a mark to lay out, and most of them
            // are nothing: an idle half minute is 180 of them.
            ForEach(timeline.sourceRows.filter { $0.value > 0 }) { row in
                BarMark(
                    x: .value("Time", row.point),
                    y: .value("Images", row.value),
                    width: .fixed(4)
                )
                .foregroundStyle(by: .value("Source", row.series))
                .cornerRadius(1)
            }
        }
    }
}

/// The work running on each of the queues the probe can see.
struct DemoQueuesChart: View, Equatable {
    let timeline: DemoHUDTimeline
    /// The limits of the three queues added up, which the work can't pass.
    let ceiling: Int

    var body: some View {
        DemoTimelineChart(
            title: "Work running",
            caption: "The three queues the probe can see, over the last 30 seconds",
            series: DemoHUDTimeline.Stage.allCases.map(\.rawValue),
            domain: timeline.domain,
            yMaximum: max(1, ceiling),
            height: 88,
            isEmpty: timeline.isEmpty
        ) {
            ForEach(timeline.stageRows) { row in
                AreaMark(
                    x: .value("Time", row.point),
                    y: .value("Running", row.value)
                )
                .foregroundStyle(by: .value("Queue", row.series))
                // A slot is taken or it isn't: the count doesn't glide from
                // one to the next, so neither does the chart.
                .interpolationMethod(.stepEnd)
            }
        }
    }
}

/// What the memory cache holds, filling and being emptied.
struct DemoMemoryCacheChart: View, Equatable {
    let timeline: DemoHUDTimeline

    var body: some View {
        let peak = timeline.points.map(\.imageCacheCost).max() ?? 0
        DemoTimelineChart(
            title: "Memory cache",
            caption: "What the decoded images take, over the last 30 seconds",
            domain: timeline.domain,
            // Follows the peak so nothing is clipped, and holds a floor so an
            // empty cache still has an axis to be empty against.
            yMaximum: max(peak, 1 << 20),
            yLabel: { demoByteCount(Int64($0)) },
            height: 72,
            isEmpty: timeline.isEmpty
        ) {
            ForEach(timeline.points) { point in
                AreaMark(
                    x: .value("Time", point.id),
                    y: .value("Bytes", point.imageCacheCost)
                )
                .foregroundStyle(DemoChartRamp.single.opacity(0.3))
                .interpolationMethod(.stepEnd)
                LineMark(
                    x: .value("Time", point.id),
                    y: .value("Bytes", point.imageCacheCost)
                )
                .foregroundStyle(DemoChartRamp.single)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.stepEnd)
            }
        }
    }
}

/// What a cache holds against the limit it is kept to, as a bar: a ratio
/// against a limit is a meter, not a chart of one bar.
///
/// A cache without a limit – or one the pipeline doesn't have – says so rather
/// than drawing a bar that would have nothing to fill.
struct DemoCacheMeter: View {
    let name: String
    /// What the cache holds, in bytes, or `nil` for a cache the pipeline
    /// hasn't got.
    let used: Int?
    /// What it is kept to. Zero where there is no limit to draw against.
    let limit: Int
    /// The note after the figures: how many images or files the cache holds.
    var detail: String?
    /// Empties the cache, where it is the app's to empty. On the row rather
    /// than in a row of buttons of its own: there is no doubt which cache a
    /// button beside the meter empties.
    var clear: (() -> Void)?

    private var fraction: Double {
        guard let used, limit > 0 else { return 0 }
        return min(1, max(0, Double(used) / Double(limit)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                    .font(.subheadline)
                Spacer(minLength: 8)
                DemoMonoLabel(figures, tint: used == nil ? .secondary : .primary)
                if let clear {
                    Button(action: clear) {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .frame(width: 22, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.secondary)
                    .disabled(used == nil)
                    .accessibilityLabel("Clear \(name) Cache")
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        // Fainter for a cache the pipeline hasn't got: an
                        // empty track next to "none" looks like a cache that
                        // happens to be empty.
                        .fill(Color.primary.opacity(used == nil ? 0.04 : 0.08))
                    Capsule()
                        .fill(DemoChartRamp.single)
                        // A cache with something in it always shows a sliver,
                        // so "a little" and "nothing" don't look the same.
                        .frame(width: max(used.map { $0 > 0 ? 3 : 0 } ?? 0, proxy.size.width * fraction))
                }
            }
            .frame(height: 5)
            .animation(.snappy, value: fraction)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) cache")
        .accessibilityValue(figures)
    }

    private var figures: String {
        guard let used else { return "none" }
        let size = limit > 0 ? "\(demoByteCount(used))/\(demoByteCount(limit))" : demoByteCount(used)
        return detail.map { "\(size) · \($0)" } ?? size
    }
}

extension Color {
    /// A color that is one hex in the light appearance and another in the dark
    /// one. The chart ramps are stepped for the surface they sit on, so
    /// neither appearance is the other one dimmed.
    fileprivate init(lightHex: UInt32, darkHex: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: darkHex) : UIColor(hex: lightHex) })
    }
}

extension UIColor {
    fileprivate convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
