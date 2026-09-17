// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// Starts and cancels image tasks at 200 a second, then reports whether the
/// pipeline kept its promises about cancellation, as a list of verdicts.
///
/// No pictures: a run is a few seconds of the pipeline under fire and a
/// sheet of pass or fail with the figures behind each. The runs are in
/// ``CancellationTortureModel``; what they hear, in ``TortureRecorder``.
struct CancellationTortureDemo: View {
    @State private var model = CancellationTortureModel()
    @State private var showsDetails = false
    @State private var showsLog = false

    var body: some View {
        List {
            controls
            if let report = model.report {
                verdicts(report)
                landings(report)
                requests(report)
            }
            slots
            if let report = model.report {
                log(report)
            }
            links
        }
        .task {
            guard DemoLaunchOptions.claimAutorun(for: .cancellationTorture) else { return }
            model.runAll()
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
                    ProgressView()
                } else {
                    Button("Run") {
                        model.runTorture()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Check Slots") {
                        model.runSlotCheck()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            HStack {
                Picker("Rate", selection: $model.rate) {
                    ForEach(CancellationTortureModel.rates, id: \.self) { rate in
                        Text("\(rate) tasks/s").tag(rate)
                    }
                }
                .labelsHidden()
                Picker("Duration", selection: $model.duration) {
                    ForEach(CancellationTortureModel.durations, id: \.self) { seconds in
                        Text("for \(seconds) s").tag(seconds)
                    }
                }
                .labelsHidden()
                Spacer()
            }
            .disabled(model.isRunning)
            DemoMonoLabel(status, tint: .primary)
            if let conditions = DemoNetworkConditions.shared.badge {
                Label("Network conditions are on (\(conditions)). They slow and fail the fixtures too, and complete every cancelled load themselves, so the slot check doesn't run.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } footer: {
            Text("Each run has a pipeline of its own with no caches, and loads fixtures: 40 ms of latency, then four chunks 15 ms apart.")
        }
    }

    private var status: String {
        switch model.status {
        case .idle:
            guard let report = model.report else {
                return "not run yet"
            }
            return "run \(report.number) · " + report.verdicts.demoSummary
        case .preparing:
            return "making the fixtures"
        case let .starting(started, total):
            return "started \(started.formatted()) of \(total.formatted())"
        case .draining(let left):
            return "waiting for \(left.formatted()) tasks to finish"
        case .checking(let step):
            return step
        case .slotCheck(let step):
            return "slot check: \(step)"
        }
    }

    // MARK: Results

    private func verdicts(_ report: TortureReport) -> some View {
        Section {
            ForEach(report.verdicts) { verdict in
                DemoVerdictRow(verdict, showsDetail: showsDetails)
            }
            if report.violationCount > 0 {
                ForEach(Array(report.violations.enumerated()), id: \.offset) { _, violation in
                    DemoMonoLabel(violation, tint: .red)
                }
            }
        } header: {
            HStack {
                Text("Run \(report.number) · \(report.rate)/s for \(report.seconds) s")
                Spacer()
                Button(showsDetails ? "Hide Details" : "Details") {
                    showsDetails.toggle()
                }
                .font(.footnote)
                .textCase(nil)
            }
        } footer: {
            if let conditions = report.conditions {
                Text("Run with the network conditions on (\(conditions)).")
            }
        }
    }

    private func landings(_ report: TortureReport) -> some View {
        Section {
            ForEach(TortureLanding.allCases, id: \.self) { landing in
                LabeledContent(landing.title.prefix(1).uppercased() + landing.title.dropFirst()) {
                    DemoMonoLabel((report.figures.landings[landing] ?? 0).formatted())
                }
            }
            LabeledContent("Never cancelled") {
                DemoMonoLabel(report.figures.notCancelledCount.formatted())
            }
        } header: {
            Text("Where the Cancels Landed")
        } footer: {
            Text("Read from each task's status, and the loads the run saw start, at the moment the app cancelled it. The second task of a coalesced pair is never cancelled.")
        }
    }

    private func requests(_ report: TortureReport) -> some View {
        Section {
            FiguresTable(
                columns: ["tasks", "cancel", "image", "fail", "calls"],
                rows: TortureKind.allCases.map { kind in
                    (kind.title, report.figures.kinds[kind] ?? .init())
                }
            )
            FiguresTable(
                columns: ["tasks", "cancel", "image", "fail", "calls"],
                rows: TortureAPI.allCases.map { api in
                    (api.title, report.figures.apis[api] ?? .init())
                }
            )
        } header: {
            Text("Requests")
        } footer: {
            let previews = report.figures.kinds[.progressive]?.previews ?? 0
            Text("By kind of request, then by the way the app listened: how each task ended, and the callbacks it made, the delegate's included. \(report.loadCount.formatted()) loads started, and the progressive JPEGs made \(previews.formatted()) previews.")
        }
    }

    private var slots: some View {
        Section {
            if let report = model.slotReport {
                if let conditions = report.skippedFor {
                    Label("Not run: the network conditions (\(conditions)) complete every cancelled load, so a silent loader gives its slots back. Switch them off to see the leak.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    DemoLink(.networkConditions)
                }
                ForEach(report.results) { result in
                    SlotRow(result: result)
                }
                let leaked = report.leakedPipelineCount
                if report.skippedFor == nil, leaked > 0 {
                    DemoMonoLabel("\(demoCount(leaked, "silent-loader pipeline")) alive for good", tint: .orange)
                }
            } else {
                Text("Check Slots cancels every download of a pipeline midway, then asks for one more image.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            DemoLink(.customDataLoader)
        } header: {
            Text("The Documented Cancel Contract")
        } footer: {
            Text("`DataLoading` says a loader calls nothing after a cancel. The pipeline gives a download's slot back only when the loader calls `completion`, so with a loader that does as it says, every download cancelled midway keeps its slot, and its pipeline, for good. A Nuke issue, not the demo's: it is on the list of framework asks. The check uses public API only – whether the delegate's `dataLoader(for:)` is called for the new request. Custom Data Loader shows one such load, call by call.")
        }
    }

    private func log(_ report: TortureReport) -> some View {
        Section {
            DisclosureGroup("Run Log", isExpanded: $showsLog) {
                ForEach(report.log) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        DemoMonoLabel(demoPad(String(format: "%.2f", line.time), to: 6))
                        Text(line.text)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var links: some View {
        Section {
            DemoLink(.imagePipeline)
            DemoLink(.priorityAndCoalescing)
        } header: {
            Text("In the Catalog")
        } footer: {
            Text("Image Pipeline cancels a task and shows its events; Priority & Coalescing cancels one of the requests sharing a download.")
        }
    }

    private static let info = DemoInfo(
        "Cancellation Torture",
        "Starts image tasks at 200 a second for five seconds, cancels them before they start, while they wait, mid-download, and after they finish, then checks what the pipeline promises about cancellation. Pass or fail, with the numbers.",
        code: """
        xcrun simctl launch booted com.github.kean.NukeDemo \\
            -demoScreen cancellation-torture -demoAutorun 1
        """,
        points: [
            .init("The mix", "Plain, processed, thumbnail, and progressive requests, and pairs of the same request that share a download. The app listens to each with `task.events`, by awaiting `task.response`, or with the completion closures, and cancels it at once, within 50 ms, in the fixture's latency, at its first chunk or preview, or after it finished. Every combination comes up every 75 requests, in the same order on every run."),
            .init("No callbacks after cancel", "The closures are called on the main thread and never after `cancel()` returns there. A stream and the delegate get nothing after `.finished`. A progress or preview event already on its way when the app cancels still arrives: the cancel reaches the pipeline with a hop. The details say how many did, and how late."),
            .init("Finished once", "Every task ends with one `.finished`, and every way of listening hears the same outcome. A task cancelled just as its image was ready may still succeed; one that succeeds more than a second after the cancel counts as a cancel ignored."),
            .init("Nothing left", "The run holds every task weakly and checks that none is left once they have finished, that the downloads, decodes, decompressions, and processing in flight are back to zero, that a new request completes, and that the pipeline goes away when the run lets go of it."),
            .init("The rate", "Tasks are started from a loop on the main thread that catches up with the clock every few milliseconds. The last verdict compares the rate reached with the one asked for."),
            .init("Slot check", "The one expected failure. A loader that follows the documented contract never calls `completion` after a cancel, so the slots of the downloads it was cancelled in are never given back, and a new request never starts. Its pipeline stays in memory, and in the HUD, for the rest of the launch."),
            .init("Fixtures", "Always fixtures, so a run compares with the last one. The network conditions of the Lab apply if they are on, and change the timing and the failures."),
            .init("-demoAutorun 1", "Runs the checks and the slot check as soon as the screen opens, once per launch, so a script can take a screenshot of the verdicts.")
        ]
    )
}

// MARK: - Rows

/// One loader of the slot check.
private struct SlotRow: View {
    let result: SlotCheck.Result

    var body: some View {
        DemoVerdictRow(state: state, title: title, figures: figures, note: note, detail: detail)
    }

    private var gotSlot: Bool {
        result.dataLoaderAfter != nil
    }

    private var state: DemoVerdict.State {
        if result.completesCancelledLoads {
            return gotSlot && result.completedAfter != nil && result.releasedAfter != nil ? .passed : .failed
        }
        return gotSlot ? .passed : .expectedFailure
    }

    private var title: String {
        result.completesCancelledLoads ? "Completing loader" : "Silent loader"
    }

    private var note: String? {
        guard !result.completesCancelledLoads else { return nil }
        return gotSlot ? "fixed in Nuke?" : "expected · Nuke issue"
    }

    /// Short lines, which fit an iPhone without wrapping.
    private var figures: String {
        let slots = "\(result.cancelledMidBody) of \(result.slotCount) slots cancelled mid-body"
        let held = "\(result.heldSlots.map(String.init) ?? "–") still held · \(result.stuckCount) stuck"
        let loader = result.dataLoaderAfter.map { "dataLoader(for:) after \(tortureDuration($0))" }
            ?? "dataLoader(for:) not called in \(demoSeconds(result.timeout))"
        let image = result.completedAfter.map { "image in \(tortureDuration($0))" } ?? "no image"
        let pipeline = result.releasedAfter == nil ? "pipeline never released" : "pipeline released"
        return [slots, held, loader, "\(image) · \(pipeline)"].joined(separator: "\n")
    }

    private var detail: String {
        if result.completesCancelledLoads {
            return "The loader calls `completion` once after a cancel, as `DataLoader` does. The slots come back, and the new request starts at once."
        }
        return gotSlot
            ? "The new request got a slot: the pipeline no longer waits for a silent loader."
            : "The loader calls nothing after a cancel, as the documentation of `DataLoading` asks, so the pipeline never gets the slots back. The new request waits for good, and the pipeline, held by that unfinished work, stays in memory: \(result.label)."
    }
}

/// Rows of counts under short column names, in the monospaced style.
private struct FiguresTable: View {
    let columns: [String]
    let rows: [(String, TortureReport.Figures.Row)]

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 3) {
            GridRow {
                Text("")
                ForEach(columns, id: \.self) { column in
                    Text(column)
                }
            }
            .foregroundStyle(.secondary)
            ForEach(rows, id: \.0) { title, row in
                GridRow {
                    Text(title)
                        .gridColumnAlignment(.leading)
                    Text(row.tasks.formatted())
                    Text(row.cancelled.formatted())
                    Text(row.images.formatted())
                    Text(row.failed.formatted())
                        .foregroundStyle(row.failed > 0 ? .orange : .primary)
                    Text(row.callbacks.formatted())
                }
            }
        }
        .font(.system(.caption2, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
