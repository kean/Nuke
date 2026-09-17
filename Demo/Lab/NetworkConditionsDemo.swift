// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// The switch that puts every download of the demo through slow, lossy, or
/// flaky network conditions, the conditions themselves, and what they have
/// done so far.
///
/// Nothing here loads an image: the conditions apply to whichever screen is
/// opened next, which is the point. The screen reads the rig's statistics four
/// times a second, the way the other instruments sample.
struct NetworkConditionsDemo: View {
    @State private var statistics = DemoConditionedDataLoader.statistics

    private typealias Preset = DemoNetworkConditions.Preset

    var body: some View {
        List {
            mode
            settings
            injected
            costs
            links
        }
        .task {
            while !Task.isCancelled {
                statistics = DemoConditionedDataLoader.statistics
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .demoInfo(Self.info)
    }

    // MARK: Sections

    private var mode: some View {
        @Bindable var conditions = DemoNetworkConditions.shared
        return Section {
            Toggle("Conditions", isOn: $conditions.isOn)
            Picker("Preset", selection: preset) {
                ForEach(Preset.allCases) { preset in
                    Text(preset.title).tag(Optional(preset))
                }
                if conditions.preset == nil {
                    Text("Custom").tag(Preset?.none)
                }
            }
            if let preset = DemoLaunchOptions.current.networkPreset {
                LabeledContent("Launched with") {
                    DemoMonoLabel("-demoNetwork \(preset.rawValue)")
                }
            }
        } footer: {
            Text("While they're on, every download of every pipeline goes through the conditions below, from the next download on, with no pipeline rebuilt. Offline, the fixtures go through them too.")
        }
    }

    private var settings: some View {
        @Bindable var conditions = DemoNetworkConditions.shared
        return Section {
            ConditionSlider("Latency", value: milliseconds($conditions.profile.latency), in: 0...2000, step: 50) {
                demoDelay($0 / 1000)
            }
            ConditionSlider("Jitter", value: milliseconds($conditions.profile.jitter), in: 0...1000, step: 25) {
                "±" + demoDelay($0 / 1000)
            }
            Picker("Bandwidth", selection: $conditions.profile.bandwidth) {
                ForEach(Self.bandwidths, id: \.self) { bandwidth in
                    Text(Self.title(bandwidth: bandwidth)).tag(bandwidth)
                }
            }
            ConditionSlider("Lost", value: $conditions.profile.lossRate, in: 0...1, step: 0.05, format: Self.percent)
            ConditionSlider("Server Errors", value: $conditions.profile.serverErrorRate, in: 0...1, step: 0.05, format: Self.percent)
            ConditionSlider("Cut Off", value: $conditions.profile.truncationRate, in: 0...1, step: 0.05, format: Self.percent)
        } header: {
            Text("Every Download")
        } footer: {
            Text("A download waits the latency, give or take the jitter, before its loader starts. Bandwidth is one link that all downloads share. Then each one is drawn in turn: lost, failing with `URLError.timedOut`; a server error, failing with `statusCodeUnacceptable(500)` as `DataLoader` does; or cut off between a fifth and four fifths of its body, failing with `URLError.networkConnectionLost`. A request `URLCache` has an answer for goes through untouched.")
        }
    }

    private var injected: some View {
        let latency = statistics.latency
        return Section {
            LabeledContent("Downloads") {
                DemoMonoLabel("\(statistics.loadCount) · \(statistics.inFlightCount) in flight")
            }
            LabeledContent("Latency") {
                DemoMonoLabel(latency.count > 0
                    ? "\(demoDelay(latency.average)) avg · \(demoDelay(latency.max)) max · \(demoSeconds(latency.total)) added"
                    : "–")
            }
            LabeledContent("Held for Bandwidth") {
                DemoMonoLabel(demoSeconds(statistics.bandwidthWait))
            }
            LabeledContent("Delivered") {
                DemoMonoLabel(demoByteCount(statistics.deliveredByteCount))
            }
            LabeledContent("Lost") {
                failures(statistics.lostCount)
            }
            LabeledContent("Server Errors") {
                failures(statistics.serverErrorCount)
            }
            LabeledContent("Cut Off") {
                failures(statistics.truncatedCount, detail: statistics.truncatedCount > 0 ? "\(demoByteCount(statistics.truncatedByteCount)) before the cut" : nil)
            }
            LabeledContent("Completed") {
                DemoMonoLabel("\(statistics.completedCount)")
            }
            LabeledContent("Failed on Their Own") {
                DemoMonoLabel("\(statistics.failedCount)")
            }
            LabeledContent("Cancelled") {
                DemoMonoLabel("\(statistics.cancelledCount)")
            }
            LabeledContent("Answered by URLCache") {
                DemoMonoLabel("\(statistics.passedToURLCacheCount) untouched")
            }
            Button("Reset Counts") {
                DemoConditionedDataLoader.resetStatistics()
                statistics = DemoConditionedDataLoader.statistics
            }
        } header: {
            Text("So Far")
        } footer: {
            Text("Every pipeline's downloads since the last reset, counted by the rig. The HUD counts the same failures for each pipeline, as failed tasks and downloads. A reset also starts over the draws of `-demoDeterministic 1`.")
        }
    }

    private func failures(_ count: Int, detail: String? = nil) -> DemoMonoLabel {
        let text = [String(count), detail].compactMap { $0 }.joined(separator: " · ")
        return DemoMonoLabel(text, tint: count > 0 ? .orange : nil)
    }

    private var costs: some View {
        Section {
            Text("The pipelines' own diagnostics, `ImageTask.Metrics`, have no `URLSession` metrics for a conditioned download, and one that `URLCache` answered reads as `network` in them: the pipeline asks a `DataLoader` for its metrics by a cast, and the rig isn't one.")
            Text("The HUD loses nothing. It counts each download where the pipeline sees it, so its time to first byte includes the latency, and still knows which ones `URLCache` answered and which reused a connection.")
            Text("A cancelled download completes at once, so a loader that goes quiet when cancelled, like Progressive Decoding's, holds no data loading slot while the conditions are on.")
        } header: {
            Text("While They're On")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var links: some View {
        Section {
            DemoLink(.imagePipeline)
            DemoLink(.uikitViews)
            DemoLink(.progressiveDecoding)
            DemoLink(.caching)
        } header: {
            Text("Try It On")
        } footer: {
            Text("Lossy or Flaky Server shows the failure states of Image Pipeline and UIKit Views. A cut-off download stops Progressive Decoding at a scan. Slow 3G shows what Caching saves the second time.")
        }
    }

    // MARK: Helpers

    private var preset: Binding<Preset?> {
        let conditions = DemoNetworkConditions.shared
        return Binding {
            conditions.preset
        } set: { preset in
            if let preset {
                conditions.profile = preset.profile
            }
        }
    }

    private func milliseconds(_ duration: Binding<Duration>) -> Binding<Double> {
        Binding {
            let components = duration.wrappedValue.components
            return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
        } set: {
            duration.wrappedValue = .milliseconds($0)
        }
    }

    private static let bandwidths: [Int?] = [nil, 5 << 20, 1 << 20, 250 << 10, 50 << 10, 20 << 10]

    private static func title(bandwidth: Int?) -> String {
        bandwidth.map { "\(demoByteCount($0))/s" } ?? "Unlimited"
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static let info = DemoInfo(
        "Network Conditions",
        "Slows down, loses, fails, and cuts off the downloads of every pipeline in the demo, so every catalog screen shows what it does on a bad network, without a line of its own.",
        code: """
        xcrun simctl launch booted com.github.kean.NukeDemo \\
            -demoNetwork lossy -demoScreen image-pipeline
        """,
        points: [
            .init("Where it sits", "The delegate of every demo pipeline returns the rig around the loader it would have used: the configured one, or a fixture loader while offline. It reads the switch for every download; off, nothing is wrapped."),
            .init("Failures", "A lost download fails with `URLError.timedOut` and a server error with `DataLoader.Error.statusCodeUnacceptable(500)`, both after the latency and before any data, and neither starts the loader. The pipeline reports either as `dataLoadingFailed`."),
            .init("Cut off", "The pipeline gets the first part of the body, with the response's full length, then `URLError.networkConnectionLost`. A progressive JPEG shows its scans up to the cut. If the server supports ranges, the pipeline keeps the part as resumable data, and the next attempt asks for the rest, through the rig again. Fixtures never resume."),
            .init("Bandwidth", "One link for every download: the slices of all of them take turns, so ten downloads at once share the rate rather than get it each."),
            .init("URLCache", "A request the `URLCache` of a `DataLoader` has a response for goes through untouched: the cache is on the device, and the rig stands for the network. It can't tell a fresh response from one the session will revalidate, so both skip the conditions."),
            .init("Cancellation", "A cancel reaches the loader at once, and the download completes with `URLError.cancelled`, once. Nothing follows the completion."),
            .init("Deterministic", "With `-demoDeterministic 1`, each download's draws come from a generator seeded by its URL and the number of times it was loaded before, so a run fails the same downloads whatever order they start in. Timings still vary.")
        ]
    )
}

/// A condition, its value, and a slider under them.
private struct ConditionSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, format: @escaping (Double) -> String) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                DemoMonoLabel(format(value), tint: value > 0 ? .primary : nil)
            }
            Slider(value: $value, in: range, step: step) {
                Text(title)
            }
        }
    }
}
