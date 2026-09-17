// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI

/// Runs a scripted workload – loads, cancels, cache churn, and animations –
/// in cycles for up to an hour, and draws the app's footprint as it goes.
///
/// A leak shows as a floor that keeps rising: the footprint each cycle comes
/// back to once its caches are emptied. The cycles and what each one left
/// behind are in ``MemorySoakModel``.
struct MemorySoakDemo: View {
    @State private var model = MemorySoakModel()
    @State private var showsDetails = false
    @State private var showsLog = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            controls
            footprint
            if let record = model.record {
                verdicts(record)
                cycles(record)
                log(record)
            }
            links
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                model.stop(.background)
            }
        }
        .task {
            // The run samples on its own; between runs, the figure stays live.
            while !Task.isCancelled {
                model.refreshFootprint()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        .task {
            guard DemoLaunchOptions.current.autoruns, !Autorun.hasRun else { return }
            Autorun.hasRun = true
            model.run()
        }
        .onDisappear {
            model.stop()
        }
        .demoInfo(Self.info)
    }

    // MARK: Controls

    private var controls: some View {
        @Bindable var model = model
        return Section {
            HStack(spacing: 12) {
                if model.isRunning {
                    Button("Stop", role: .destructive) {
                        model.stop()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.status == .stopping)
                    ProgressView()
                } else {
                    Button("Run") {
                        model.run()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Picker("Duration", selection: $model.minutes) {
                    ForEach(MemorySoakModel.durations, id: \.self) { minutes in
                        Text(minutes < 60 ? "for \(minutes) min" : "for an hour").tag(minutes)
                    }
                }
                .labelsHidden()
                .disabled(model.isRunning)
                Spacer()
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            DemoMonoLabel(status, tint: .primary)
        } footer: {
            Text("The screen stays awake while a run goes on. Leaving the screen, or the app, stops it; the cycles so far stay until the next run.")
        }
    }

    private var status: String {
        switch model.status {
        case .idle:
            guard let record = model.record else {
                return "not run yet"
            }
            let cycles = record.cycles.count == 1 ? "1 cycle" : "\(record.cycles.count) cycles"
            return "run \(record.number) · \(record.end?.title ?? "") · \(cycles) in \(soakTime(record.elapsed))"
        case .preparing:
            return "making the fixtures"
        case let .running(cycle, phase):
            let total = TimeInterval(model.minutes * 60)
            return "cycle \(cycle) · \(phase.title) · \(soakTime(model.record?.elapsed ?? 0)) of \(soakTime(total))"
        case .stopping:
            return "letting go of the pipeline"
        }
    }

    // MARK: Footprint

    private var footprint: some View {
        Section {
            let record = model.record
            let duration = max(TimeInterval((record?.minutes ?? model.minutes) * 60), record?.elapsed ?? 0)
            VStack(alignment: .leading, spacing: 8) {
                DemoSparkline(
                    samples: record?.samples ?? [],
                    ticks: record?.warnings.map(\.time) ?? [],
                    duration: duration
                )
                .frame(height: 96)
                .overlay {
                    if record == nil {
                        Text("Run draws the footprint here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let record, !record.cycles.isEmpty {
                    floors(record, duration: duration)
                        .frame(height: 64)
                }
                DemoMonoLabel(figures(record), tint: .primary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                players
            }
            .padding(.vertical, 4)
        } header: {
            Text("Footprint")
        } footer: {
            Text("`phys_footprint`, twice a second, with an orange tick at each memory warning. Below it, closer up, each cycle's floor – the footprint once its caches were emptied – and the slope fitted to them from cycle 2 on. The heap is what the `malloc` zones hold. Then the cycle's animations while they play.")
        }
    }

    /// The floors, with the room between the lowest and the highest of them,
    /// and the fitted slope.
    private func floors(_ record: SoakRecord, duration: TimeInterval) -> some View {
        let floors = record.cycles.map { DemoSparkline.Sample(time: $0.endedAt, value: Double($0.floor)) }
        let values = floors.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let padding = max((high - low) * 0.15, 256 * 1_024)
        var trend: (from: DemoSparkline.Sample, to: DemoSparkline.Sample)?
        if let growth = record.growth, let first = record.countedCycles.first, let last = record.countedCycles.last {
            trend = (
                DemoSparkline.Sample(time: first.endedAt, value: growth.fitted.first),
                DemoSparkline.Sample(time: last.endedAt, value: growth.fitted.last)
            )
        }
        return DemoSparkline(
            samples: floors,
            dots: floors,
            trend: trend,
            duration: duration,
            range: (low - padding)...(high + padding),
            tint: .secondary
        )
    }

    private func figures(_ record: SoakRecord?) -> String {
        let footprint = model.footprint
        var first = [footprint.current.map { "now \(demoByteCount($0))" } ?? "now –"]
        if let record {
            first.append("start \(demoByteCount(record.startFootprint))")
            if record.samplePeak > 0 {
                first.append("peak \(demoByteCount(record.samplePeak))")
            }
        }
        if let available = footprint.available {
            first.append("\(demoByteCount(available)) free")
        }
        var lines = [first.joined(separator: " · ")]
        if let record, let last = record.cycles.last {
            lines.append("floor \(demoByteCount(last.floor))" + slope(record, .footprint))
            lines.append("heap  \(demoByteCount(last.heap))" + slope(record, .heap))
        }
        return lines.joined(separator: "\n")
    }

    private func slope(_ record: SoakRecord, _ measure: SoakRecord.Measure) -> String {
        guard let growth = record.growth(of: measure), growth.cycleCount >= SoakRecord.minimumCycleCount else {
            return ""
        }
        return String(format: " · %+.2f MB/min", growth.slope / 1_048_576)
    }

    private var players: some View {
        HStack(spacing: 6) {
            ForEach(0..<6, id: \.self) { index in
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.05))
                    if model.players.indices.contains(index) {
                        let player = model.players[index]
                        AnimatedImage(player: player.player, poster: player.poster)
                            .resizable()
                            .scaledToFit()
                            .id(player.id)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: Results

    private func verdicts(_ record: SoakRecord) -> some View {
        Section {
            ForEach(record.verdicts) { verdict in
                DemoVerdictRow(verdict, showsDetail: showsDetails)
            }
            LabeledContent("Peak") {
                DemoMonoLabel(peak(record))
            }
        } header: {
            HStack {
                Text("Run \(record.number) · \(record.minutes < 60 ? "\(record.minutes) min" : "1 hour")")
                Spacer()
                Button(showsDetails ? "Hide Details" : "Details") {
                    showsDetails.toggle()
                }
                .font(.footnote)
                .textCase(nil)
            }
        } footer: {
            Text("The peak of the samples, twice a second. The kernel's own peak, since the app launched, misses nothing between them; it is shown when the run raised it.")
        }
    }

    private func peak(_ record: SoakRecord) -> String {
        let sampled = "\(demoByteCount(record.samplePeak)) · +\(demoByteCount(max(0, record.samplePeak - record.startFootprint)))"
        guard record.lifetimePeak > record.startLifetimePeak else {
            return sampled
        }
        return sampled + " · kernel \(demoByteCount(record.lifetimePeak))"
    }

    private func cycles(_ record: SoakRecord) -> some View {
        Section {
            if record.cycles.isEmpty {
                Text("The first cycle takes about five seconds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(record.cycles.suffix(Self.shownCycleCount).reversed()) { cycle in
                CycleRow(cycle: cycle, baseline: record.countedCycles.first?.floor)
            }
        } header: {
            Text("Cycles")
        } footer: {
            let hidden = record.cycles.count - Self.shownCycleCount
            Text((hidden > 0 ? "The last \(Self.shownCycleCount), newest first; the \(hidden) before them are dots on the line above. " : "Newest first. ")
                + "Each: the floor and how far it is from cycle 2's, the heap, and the peak; the loads cancelled, the decodes, and what was done to a cache halfway; what was left once it was over.")
        }
    }

    private static let shownCycleCount = 20

    private func log(_ record: SoakRecord) -> some View {
        Section {
            DisclosureGroup("Run Log", isExpanded: $showsLog) {
                ForEach(record.log) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        DemoMonoLabel(demoPad(soakTime(line.time), to: 5))
                        Text(line.text)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var links: some View {
        Section {
            DemoLink(.caching)
            DemoLink(.animatedImages)
        } header: {
            Text("In the Catalog")
        } footer: {
            Text("Caching shows what the memory and disk caches keep; Animated Images, what a player holds of an animation.")
        }
    }

    private static let info = DemoInfo(
        "Memory Soak",
        "Runs the same five seconds of work over and over, for a minute or up to an hour, and watches whether the app's footprint comes back to where it was after each round. Catches the growth that no unit test runs long enough to see.",
        code: """
        xcrun simctl launch booted com.github.kean.NukeDemo \\
            -demoScreen memory-soak -demoAutorun 1
        """,
        points: [
            .init("A cycle", "Six animations start – the 200-frame GIF three times, one of them smaller, the GIF, the APNG, and the animated WebP – and are dropped 3.5 s later. 150 loads start over 3 s: the 12 MP JPEG in full and as a thumbnail, photos resized, cropped, blurred, and as thumbnails, a PNG, a GIF, and a JPEG; a third are cancelled within 30 ms, most of them before their data arrives. Halfway, the memory cache is emptied or trimmed, or the disk cache emptied, in turn. Once the loads are done, both caches are emptied, and a second later the footprint is read five times: the median is the cycle's floor."),
            .init("Growth", "The slope of the floors against time, from cycle 2 on: the first cycle pays for what the app sets up once. Each floor is read twice: the footprint, and the heap – the bytes in use in the `malloc` zones, where every object of Nuke's is. The footprint fails above 2 MB a minute, which a cycle keeping one decoded photo would pass; the heap above 0.5 MB, about 250 bytes kept per load. Either only if it also stands out from the noise by three standard errors. A minute makes about twelve cycles; an hour, about seven hundred."),
            .init("The simulator", "On the simulator, the footprint of a healthy run grows 0.3–1.3 MB a minute over its first minutes, mostly outside the heap, and levels off at about 0.07 MB a minute after a quarter of an hour. The heap grew about 0.1 MB a minute for a whole hour, which nothing the soak counts accounts for."),
            .init("What's left", "After each cycle: its `ImageTask`s and players still in memory, the players and animations the frame pool still has, the entries in both caches, and the pipelines alive. A floor that rises while these stay at zero is a leak; one that rises with them is something still held. The frame pool keeps the frames of an animation nobody plays until it next divides its budget, even after the cache let go of the animation, so it is asked to give them back first, and what it kept is shown on the cycle."),
            .init("Memory warnings", "30 s into a run, and every two minutes after, the churn is a posted `UIApplication.didReceiveMemoryWarningNotification`. The frame pool holds its animations at two frames for a minute after one; `ImageCache` empties itself on the system's memory-pressure event instead, which a posted notification doesn't raise."),
            .init("The pipeline", "The run's own, with fixtures 20 ms away, a 256 MB memory cache that takes the 46 MB bitmap of the 12 MP image, and a disk cache that stores the data and every processed image. Both are emptied at the start and the end, and the pipeline has to go when the run is over."),
            .init("Keeping it running", "The screen stays awake while a run goes on. Leaving the screen stops it, and so does leaving the app, where it would be suspended. Stopping keeps the cycles finished so far."),
            .init("On a device", "The simulator has no memory limit, so a leak there only grows. On a device, the figures also say how much more the app can take before the system ends it, from `os_proc_available_memory()`."),
            .init("-demoAutorun 1", "Starts a one-minute run as soon as the screen opens, once per launch, so a script can take a screenshot of the line and the verdicts.")
        ]
    )
}

/// Runs on its own only once per launch, not each time the screen comes
/// back.
@MainActor
private enum Autorun {
    static var hasRun = false
}

/// One cycle: its floor and peak, what it did, and what it left.
private struct CycleRow: View {
    let cycle: SoakCycle
    let baseline: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            DemoMonoLabel(first, tint: .primary)
            DemoMonoLabel(second)
            DemoMonoLabel(third, tint: cycle.left.isClean ? nil : .orange)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var first: String {
        var text = "\(demoPad(String(cycle.number), to: 3)) · \(soakTime(cycle.endedAt)) · floor \(demoByteCount(cycle.floor))"
        if let baseline, cycle.number > SoakRecord.warmUpCycleCount {
            text += String(format: " %+.1f", Double(cycle.floor - baseline) / 1_048_576)
        }
        return text + " · heap \(demoByteCount(cycle.heap)) · peak \(demoByteCount(cycle.peak))"
    }

    private var second: String {
        "\(cycle.cancelCount) of \(cycle.loadCount) cancelled · \(cycle.decodeCount) decodes · \(cycle.churn.title)"
            + (cycle.failureCount > 0 ? " · \(cycle.failureCount) failed" : "")
    }

    private var third: String {
        let left = cycle.left
        let parts = [
            (left.tasks, "tasks"),
            (left.players, "players"),
            (left.poolAnimations, "animations"),
            (left.imageCacheCount, "images"),
            (left.dataCacheCount, "files")
        ].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        let pipelines = left.pipelines == 1 ? "1 pipeline" : "\(left.pipelines) pipelines"
        var text = (parts.isEmpty ? "nothing left" : "left " + parts.joined(separator: ", ")) + " · \(pipelines)"
        if cycle.poolKeptAnimations > 0 {
            text += " · pool kept \(cycle.poolKeptAnimations), \(demoByteCount(cycle.poolKeptBytes))"
        }
        return text
    }
}

/// "1:05"
private func soakTime(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.down))
    return "\(total / 60):" + String(format: "%02d", total % 60)
}
