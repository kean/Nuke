// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

// What the stress screens of the Lab report instead of pictures: a verdict per
// thing a run checks, and a line of the samples it took along the way.

/// One thing a Lab run checks, and how it came out.
struct DemoVerdict: Identifiable, Sendable {
    enum State: Sendable {
        case passed
        case failed
        /// A failure that comes from Nuke as it is, not from the demo.
        case expectedFailure
        case skipped
    }

    let title: String
    let state: State
    let figures: String
    let detail: String

    var id: String { title }
}

/// A mark, what was checked, and the figures.
struct DemoVerdictRow: View {
    let state: DemoVerdict.State
    let title: String
    let figures: String
    var note: String?
    let detail: String?

    init(state: DemoVerdict.State, title: String, figures: String, note: String? = nil, detail: String?) {
        self.state = state
        self.title = title
        self.figures = figures
        self.note = note
        self.detail = detail
    }

    /// A verdict, with its detail only when asked for: the default shot of a
    /// report is the list of marks and figures.
    init(_ verdict: DemoVerdict, showsDetail: Bool, note: String? = nil) {
        self.init(state: verdict.state, title: verdict.title, figures: verdict.figures, note: note, detail: showsDetail ? verdict.detail : nil)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .imageScale(.medium)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let note {
                        Spacer(minLength: 8)
                        Text(note)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                }
                DemoMonoLabel(figures)
                if let detail {
                    Text(LocalizedStringKey(detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var symbol: String {
        switch state {
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .expectedFailure: "xmark.circle"
        case .skipped: "minus.circle"
        }
    }

    private var tint: Color {
        switch state {
        case .passed: .green
        case .failed: .red
        case .expectedFailure: .orange
        case .skipped: .secondary
        }
    }
}

extension Collection<DemoVerdict> {
    /// "3 passed · 1 failed", leaving out the states nothing is in.
    var demoSummary: String {
        [
            (DemoVerdict.State.passed, "passed"),
            (.failed, "failed"),
            (.expectedFailure, "expected to fail"),
            (.skipped, "skipped")
        ].compactMap { state, title in
            let count = self.count { $0.state == state }
            return count > 0 ? "\(count) \(title)" : nil
        }.joined(separator: " · ")
    }
}

// MARK: - Sparkline

/// Samples over time as a line, with the lowest and highest sample under each
/// point of its width filled in between, so an hour of samples draws as fast
/// as a minute of them.
///
/// It has no axes: the screen writes the figures that matter beside it. What
/// it can add is a dashed rule at a value (a limit, a baseline), named in a
/// legend in the corner, a dot at each sample worth pointing at, a dashed
/// trend from one point to another, and a tick along the bottom at a moment
/// (a sweep, a memory warning).
struct DemoSparkline: View {
    struct Sample: Sendable {
        /// Seconds since the start of the run.
        let time: TimeInterval
        let value: Double
    }

    struct Rule: Identifiable {
        let value: Double
        let label: String
        var color: Color = .secondary

        var id: String { label }
    }

    var samples: [Sample]
    var dots: [Sample] = []
    var rules: [Rule] = []
    /// A straight line between two points, such as a fitted slope.
    var trend: (from: Sample, to: Sample)?
    var ticks: [TimeInterval] = []
    /// The time the line spans, which may run past the last sample: a run
    /// in progress fills its width as it goes.
    var duration: TimeInterval?
    /// The values from the bottom edge to the top one. By default, from the
    /// lowest to the highest sample or rule, with a little room.
    var range: ClosedRange<Double>?
    var tint: Color = .accentColor

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topLeading) {
            if !rules.isEmpty {
                legend
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    /// The rules' names, over the line rather than in it.
    private var legend: some View {
        HStack(spacing: 8) {
            ForEach(rules) { rule in
                Text("┄ " + rule.label)
                    .foregroundStyle(rule.color)
            }
        }
        .font(.system(size: 9, design: .monospaced))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.thinMaterial, in: Capsule())
        .padding(4)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let span = max(duration ?? 0, samples.last?.time ?? 0, 1)
        let range = self.range ?? defaultRange
        let height = range.upperBound - range.lowerBound
        let inset: CGFloat = 4
        let plot = CGRect(x: 0, y: inset, width: size.width, height: size.height - inset * 2)
        func x(_ time: TimeInterval) -> CGFloat {
            plot.minX + CGFloat(time / span) * plot.width
        }
        func y(_ value: Double) -> CGFloat {
            plot.maxY - CGFloat((value - range.lowerBound) / max(height, 1)) * plot.height
        }

        for tick in ticks {
            var path = Path()
            path.move(to: CGPoint(x: x(tick), y: size.height))
            path.addLine(to: CGPoint(x: x(tick), y: size.height - 6))
            context.stroke(path, with: .color(.orange), lineWidth: 1)
        }

        // One column per point: the lowest, highest, and average sample in it.
        var columns: [(x: CGFloat, low: Double, high: Double, mean: Double)] = []
        var current: (column: Int, low: Double, high: Double, sum: Double, count: Int)?
        for sample in samples {
            let column = Int(x(sample.time))
            if let value = current, value.column == column {
                current = (column, min(value.low, sample.value), max(value.high, sample.value), value.sum + sample.value, value.count + 1)
            } else {
                if let value = current {
                    columns.append((CGFloat(value.column), value.low, value.high, value.sum / Double(value.count)))
                }
                current = (column, sample.value, sample.value, sample.value, 1)
            }
        }
        if let value = current {
            columns.append((CGFloat(value.column), value.low, value.high, value.sum / Double(value.count)))
        }

        if columns.count > 1 {
            var band = Path()
            band.move(to: CGPoint(x: columns[0].x, y: y(columns[0].high)))
            for column in columns.dropFirst() {
                band.addLine(to: CGPoint(x: column.x, y: y(column.high)))
            }
            for column in columns.reversed() {
                band.addLine(to: CGPoint(x: column.x, y: y(column.low)))
            }
            band.closeSubpath()
            context.fill(band, with: .color(tint.opacity(0.25)))

            var line = Path()
            line.move(to: CGPoint(x: columns[0].x, y: y(columns[0].mean)))
            for column in columns.dropFirst() {
                line.addLine(to: CGPoint(x: column.x, y: y(column.mean)))
            }
            context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }

        for rule in rules {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y(rule.value)))
            path.addLine(to: CGPoint(x: size.width, y: y(rule.value)))
            context.stroke(path, with: .color(rule.color.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }

        if let trend {
            var path = Path()
            path.move(to: CGPoint(x: x(trend.from.time), y: y(trend.from.value)))
            path.addLine(to: CGPoint(x: x(trend.to.time), y: y(trend.to.value)))
            context.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
        }

        // Smaller as they crowd, so that an hour of them is still a line.
        let radius = min(2.5, max(0.75, plot.width / CGFloat(max(dots.count, 1)) / 3))
        for dot in dots {
            let point = CGPoint(x: x(dot.time), y: y(dot.value))
            context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)), with: .color(.primary))
        }
    }

    private var defaultRange: ClosedRange<Double> {
        let values = samples.map(\.value) + dots.map(\.value) + rules.map(\.value) + [trend?.from.value, trend?.to.value].compactMap { $0 }
        guard let low = values.min(), let high = values.max() else {
            return 0...1
        }
        let padding = max((high - low) * 0.1, 1)
        return (low - padding)...(high + padding)
    }
}
