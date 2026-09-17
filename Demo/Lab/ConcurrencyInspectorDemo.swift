// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import SwiftUI

/// The five task queues of a pipeline, every task of a workload and where it
/// is, and the stalls of the main thread, sampled ten times a second.
///
/// A list of figures rather than pictures: a map of the tasks by state, the
/// queues with their limits and a switch each, the stalls, and the tasks in
/// flight. On an iPad the tasks get a column of their own. The runs are in
/// ``ConcurrencyInspectorModel``; what they hear, in ``InspectorRecorder``.
struct ConcurrencyInspectorDemo: View {
    @State private var model = ConcurrencyInspectorModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        content
            .task(id: scenePhase == .active) {
                guard scenePhase == .active else { return }
                model.startWatching()
                defer { model.stopWatching() }
                await demoWaitUntilCancelled()
            }
            .task {
                guard DemoLaunchOptions.claimAutorun(for: .concurrencyInspector) else { return }
                model.workload = .burst
                model.start()
            }
            .onChange(of: scenePhase) {
                // A trickle or a scroll would catch up with its clock on the
                // way back, all at once.
                if scenePhase == .background {
                    model.leave()
                }
            }
            .onDisappear {
                model.leave()
            }
            .demoInfo(Self.info)
    }

    @ViewBuilder
    private var content: some View {
        if horizontalSizeClass == .regular {
            HStack(spacing: 0) {
                List {
                    workload
                    queues
                    mainThread
                    pipelines
                    links
                }
                Divider()
                List {
                    tasks
                    taskRows
                }
            }
        } else {
            List {
                workload
                tasks
                queues
                mainThread
                taskRows
                pipelines
                links
            }
        }
    }

    // MARK: Workload

    private var workload: some View {
        @Bindable var model = model
        return Section {
            Picker("Workload", selection: $model.workload) {
                ForEach(InspectorWorkload.allCases) { workload in
                    Text(workload.title).tag(workload)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.isRunning)
            Text(model.workload.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if model.isRunning {
                    if model.status == .running, model.run?.workload != .burst {
                        Button("Stop") {
                            model.stop()
                        }
                    }
                    Button(model.isPaused ? "Resume" : "Pause") {
                        if model.isPaused {
                            model.resume()
                        } else {
                            model.pause()
                        }
                    }
                    Button("Cancel All", role: .destructive) {
                        model.cancelAll()
                    }
                } else {
                    Button("Start") {
                        model.start()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer(minLength: 0)
                if model.isRunning {
                    ProgressView()
                }
            }
            .buttonStyle(.bordered)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            DemoMonoLabel(status, tint: model.isPaused ? .orange : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let conditions = DemoNetworkConditions.shared.badge {
                Label("Network conditions are on (\(conditions)): the fixtures are slowed, and some fail.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Workload")
        } footer: {
            Text("Each run has a pipeline of its own, with no memory cache and fixtures that take 0.3 s each. Pause stops the workload and suspends all five queues: what is running finishes, and the rest waits where it is.")
        }
    }

    private var status: String {
        let run = model.run
        let sample = model.sample
        switch model.status {
        case .idle:
            return "not run yet"
        case .preparing:
            return "run \(run?.number ?? 0) · making the fixtures"
        case .running, .stopping, .finished:
            let elapsed = (run?.endedAt ?? sample.time) - (run?.startedAt ?? sample.time)
            let finished = sample.count(.image) + sample.count(.cancelled) + sample.count(.failed)
            var parts = [
                "run \(run?.number ?? 0)",
                run?.workload.title.lowercased() ?? "",
                "\(finished.formatted()) of \(sample.taskCount.formatted()) done",
                demoSeconds(max(0, elapsed))
            ]
            if model.isPaused {
                parts.append("paused")
            } else if model.status == .stopping {
                parts.append("stopping")
            } else if model.status == .finished {
                parts.append("over")
            }
            return parts.joined(separator: " · ")
        }
    }

    // MARK: Tasks

    private var tasks: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                InspectorTaskMap(cells: model.sample.cells)
                InspectorLegend(sample: model.sample)
                sparkline
                DemoMonoLabel(taskFigures, tint: .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Tasks")
        } footer: {
            Text("A square per task, oldest first, the last \(InspectorRecorder.cellLimit) of them; a hollow one is waiting. Under it, the tasks unfinished over the last \(Int(ConcurrencyInspectorModel.seriesDuration)) s, with an orange tick where the main thread stalled.")
        }
    }

    private var sparkline: some View {
        let now = model.sample.time
        let start = now - ConcurrencyInspectorModel.seriesDuration
        let samples = model.series.map { DemoSparkline.Sample(time: $0.time - start, value: $0.value) }
        let ticks = model.stalls.map { $0.startedAt - start }.filter { $0 >= 0 }
        let peak = model.series.map(\.value).max() ?? 0
        return DemoSparkline(
            samples: samples,
            ticks: ticks,
            duration: ConcurrencyInspectorModel.seriesDuration,
            range: 0...max(10, peak * 1.1),
            tint: .blue
        )
        .frame(height: 44)
    }

    private var taskFigures: String {
        let sample = model.sample
        let failed = sample.count(.failed)
        return "\(sample.activeCount.formatted()) unfinished · \(sample.count(.image).formatted()) images · \(sample.count(.cancelled).formatted()) cancelled"
            + (failed > 0 ? " · \(failed.formatted()) failed" : "")
    }

    private var taskRows: some View {
        Group {
            Section {
                if model.sample.active.isEmpty {
                    Text(model.isRunning ? "Every task has finished." : "Start runs a workload.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    InspectorTaskTable(rows: model.sample.active, hiddenCount: model.sample.hiddenActiveCount)
                }
            } header: {
                Text("In Flight · \(model.sample.activeCount.formatted())")
            } footer: {
                Text("Oldest first, the first \(InspectorRecorder.activeRowLimit): the request's number (b for the second of a pair), its kind, its priority, where it is, and its age. \"12mp\" is the 12 MP JPEG, and \"12mp·t\" a thumbnail of it.")
            }
            if !model.sample.finished.isEmpty {
                Section {
                    InspectorTaskTable(rows: model.sample.finished, hiddenCount: 0)
                } header: {
                    Text("Finished Last")
                } footer: {
                    Text("Newest first, with the time each took.")
                }
            }
        }
    }

    // MARK: Queues

    private var queues: some View {
        Section {
            ForEach(model.queues) { status in
                InspectorQueueRow(model: model, status: status)
            }
        } header: {
            Text("Queues · \(model.pipelineLabel)")
        } footer: {
            Text("Running is the probe's count of the work on each queue, and the screen's own for processing (*), which the probe can't see. `TaskQueue` keeps the work it holds to itself, so waiting is the screen's count of its own requests: a download waits for the rate limiter too, and an encode is for the disk cache, after its task finished. Only a thumbnail's decode uses the decoding queue. The limits and switches apply to the next run's pipeline too.")
        }
    }

    // MARK: Main Thread

    private var mainThread: some View {
        Section {
            HStack(spacing: 10) {
                Button("Stall 50 ms") {
                    model.stallMainThread(for: 50)
                }
                Button("Stall 200 ms") {
                    model.stallMainThread(for: 200)
                }
                Spacer(minLength: 0)
                Button("Clear") {
                    model.clearStalls()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            VStack(alignment: .leading, spacing: 2) {
                DemoMonoLabel(displayLine, tint: .primary)
                DemoMonoLabel(pingLine, tint: .primary)
                DemoMonoLabel(costLine)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            if model.stalls.isEmpty {
                Text("No stall over 16 ms since the screen opened or was cleared.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.stalls.reversed()) { stall in
                InspectorStallRow(stall: stall)
            }
        } header: {
            Text("Main Thread")
        } footer: {
            Text("Stalls over 16 ms, newest first. The display link sees one as a frame that came a refresh or more late, and the stall as the frame less a refresh. A thread of the screen's own hands the main queue a block every 10 ms and times how long it waits. Both run only while the screen is open.")
        }
    }

    private var displayLine: String {
        let display = model.display
        let rate = display.framesPerSecond.map { "\(Int($0.rounded())) fps" } ?? "– fps"
        return "display \(demoPad(rate, to: 7)) · \(demoPad(display.hitchCount.formatted(), to: 3)) late · \(demoPad(demoDelay(display.longestFrame), to: 6)) worst frame"
    }

    private var pingLine: String {
        let ping = model.ping
        guard ping.pingCount > 0 else {
            return "ping    –"
        }
        return "ping    \(demoPad(demoMilliseconds(ping.averageLatency), to: 7)) avg · \(demoPad(ping.stallCount.formatted(), to: 3)) over · \(demoPad(demoDelay(ping.maxLatency), to: 6)) worst wait"
    }

    private var costLine: String {
        let cost = model.samplingCost
        return "sample  \(demoPad(demoMilliseconds(cost.average), to: 7)) avg · \(demoMilliseconds(cost.max)) worst, to read the record"
    }

    // MARK: Pipelines

    private var pipelines: some View {
        Section {
            InspectorPipelinesTable(pipelines: model.pipelines)
        } header: {
            Text("Every Pipeline")
        } footer: {
            Text("The five queues of every pipeline alive: the work the probe sees running against the limit, orange while the queue is suspended. A dash is work the probe can't see. Only this screen's pipeline can be changed from here.")
        }
    }

    private var links: some View {
        Section {
            DemoLink(.pipelineHUD)
            DemoLink(.priorityAndCoalescing)
        } header: {
            Text("See Also")
        } footer: {
            Text("The HUD counts the same queues for any pipeline, over any screen. Priority & Coalescing shows the order the data loading queue starts downloads in.")
        }
    }

    // MARK: Info

    private static let info = DemoInfo(
        "Concurrency Inspector",
        "The five task queues of a pipeline, where each task of a workload is, and how long the main thread stalls, ten times a second. A change to how the pipeline schedules its work shows here first.",
        code: """
        xcrun simctl launch booted com.github.kean.NukeDemo \\
            -demoScreen concurrency-inspector -demoAutorun 1
        """,
        points: [
            .init("Workloads", "Burst starts 240 requests at once, with a sixth of them high priority and a sixth low. Trickle starts eight a second, which the queues keep up with. Scroll starts four a row, eight rows a second, the way a fast scroll through a grid with prefetching would: low half a second early, normal while the row shows, cancelled when it leaves. That is more than the queues take, so the cancels are what keeps the line short."),
            .init("The requests", "Photos, decoded on the pipeline's actor and decompressed; photos resized and blurred on the processing queue; photos and the 12 MP JPEG as thumbnails, decoded on the decoding queue; the 12 MP JPEG in full, which has the longest decompression; and pairs of one request, which share all the work. Every request has a URL of its own. The pipeline's disk cache keeps nothing, so the thumbnails and blurred photos are encoded for it on the encoding queue, and no file is written."),
            .init("Where a task is", "Created until the pipeline starts it; queued until its download has a slot, the rate limiter included; loading until the first byte, and receiving until the last. Then waiting for a queue and running on it, in turn: decoding, processing, and decompressing, as its kind needs. A hollow square waits. A task is finished when its `.finished` event arrives: with an image, cancelled, or failed."),
            .init("How it's heard", "The pipeline's delegate: when each task starts and finishes, the decoder and encoder it returns, `shouldDecompress`, which the pipeline asks right before it queues a decompression, and `decompress`. The resize-and-blur processor tells the screen when it runs. The probe reports each call to the loader. Every hook does what Nuke's own does."),
            .init("Queues", "`TaskQueue` makes its limit and its suspension public, and keeps its counts to itself. Running comes from the probe, which counts the work as it passes, and processing from the screen's processor. Waiting is what the screen knows of its own requests; it doesn't know the order they will start in. Priority & Coalescing keeps that order for downloads."),
            .init("Suspend and limits", "Suspending a queue lets what is running finish and starts nothing more, and resuming it starts what waited. A limit takes effect at the next start. Both apply to the screen's pipeline only, at once, and to the pipeline of every run after. Suspend decoding, processing, and decompressing during a burst, and the tasks gather in front of each."),
            .init("Main thread", "Stalls over 16 ms, as the display link saw them – a frame that arrived a refresh or more late, less the refresh – and as a thread that hands the main queue a block every 10 ms saw them: how long the block waited. The pinger needs no display and catches a backlog of short work too. Stall 50 ms and Stall 200 ms block the main thread, for the watchdog to catch."),
            .init("Cost", "A lock and a pass over the record ten times a second, lines for at most 60 tasks, set as one text per section, a display link, and a block on the main queue a hundred times a second, only while the screen is open. The sample line says how long reading the record takes. A long run lets go of its oldest finished tasks past 1,200."),
            .init("-demoAutorun 1", "Starts a burst as soon as the screen opens, once per launch, so a script can take a screenshot of the tasks in flight.")
        ]
    )
}

// MARK: - Tasks

extension InspectorState {
    var color: Color {
        switch self {
        case .notStarted, .queued: .gray
        case .loading, .receiving: .blue
        case .decodeWaiting, .decoding: .purple
        case .processWaiting, .processing: .orange
        case .decompressWaiting, .decompressing: .teal
        case .image: .green
        case .cancelled: .yellow
        case .failed: .red
        }
    }

    /// Hollow while the task waits, with a created task paler than a queued
    /// one.
    var isHollow: Bool {
        isWaiting && self != .notStarted
    }

    var opacity: Double {
        switch self {
        case .notStarted: 0.35
        case .loading: 0.55
        default: 1
        }
    }
}

/// A square per task, drawn in one pass however many there are.
private struct InspectorTaskMap: View {
    let cells: [InspectorState]

    private static let cell: CGFloat = 8
    private static let spacing: CGFloat = 2

    @State private var width: CGFloat = 300

    var body: some View {
        let perRow = max(1, Int((width + Self.spacing) / (Self.cell + Self.spacing)))
        // As tall as the cells need, and never less than four rows, so the
        // list doesn't jump while the first tasks come in.
        let rows = max(4, (cells.count + perRow - 1) / perRow)
        Canvas { context, _ in
            for (index, state) in cells.enumerated() {
                let rect = CGRect(
                    x: CGFloat(index % perRow) * (Self.cell + Self.spacing),
                    y: CGFloat(index / perRow) * (Self.cell + Self.spacing),
                    width: Self.cell,
                    height: Self.cell
                )
                let color = state.color.opacity(state.opacity)
                if state.isHollow {
                    context.stroke(Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 1.5), with: .color(color), lineWidth: 1.5)
                } else {
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
                }
            }
        }
        .frame(height: CGFloat(rows) * (Self.cell + Self.spacing))
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .overlay {
            if cells.isEmpty {
                Text("A square per task")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The count of tasks in each state, in the order a task goes through them.
private struct InspectorLegend: View {
    let sample: InspectorSample

    var body: some View {
        // Two columns, so each row is a stage: waiting for it, then in it.
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6, alignment: .leading), GridItem(.flexible(), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 3) {
            ForEach(InspectorState.allCases.filter(\.isActive), id: \.self) { state in
                HStack(spacing: 5) {
                    InspectorStateMark(state: state)
                    Text("\(demoPad(sample.count(state).formatted(), to: 3)) \(state.title)")
                        .foregroundStyle(sample.count(state) > 0 ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .font(.system(.caption2, design: .monospaced))
    }
}

private struct InspectorStateMark: View {
    let state: InspectorState

    var body: some View {
        let color = state.color.opacity(state.opacity)
        RoundedRectangle(cornerRadius: 2)
            .fill(state.isHollow ? Color.clear : color)
            .overlay {
                if state.isHollow {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(color, lineWidth: 1.5)
                }
            }
            .frame(width: 9, height: 9)
    }
}

/// Tasks, a line each: the mark of where it is, its number, kind, and
/// priority, where it is, and its age.
///
/// Drawn rather than laid out as rows. Tasks come and go every sample, and a
/// list that inserted, removed, and redrew a row for each dropped frames on
/// an iPad with sixty of them on screen; so did one text of sixty lines that
/// the list measured again every time. The canvas changes height only in
/// steps of five lines.
private struct InspectorTaskTable: View {
    let rows: [InspectorRow]
    let hiddenCount: Int

    private static let lineHeight: CGFloat = 16
    private static let font = Font.system(.caption2, design: .monospaced)

    var body: some View {
        let lineCount = rows.count + (hiddenCount > 0 ? 1 : 0)
        // The most lines a table has: the rows and "and N more".
        let shownLineCount = min((lineCount + 4) / 5 * 5, InspectorRecorder.activeRowLimit + 1)
        Canvas { context, _ in
            for (index, row) in rows.enumerated() {
                let y = CGFloat(index) * Self.lineHeight
                let state = row.state
                let mark = CGRect(x: 0, y: y + 3.5, width: 9, height: 9)
                let color = state.color.opacity(state.opacity)
                if state.isHollow {
                    context.stroke(Path(roundedRect: mark.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 1.5), with: .color(color), lineWidth: 1.5)
                } else {
                    context.fill(Path(roundedRect: mark, cornerRadius: 2), with: .color(color))
                }
                let text = Text(Self.line(row))
                    .font(Self.font)
                    .foregroundStyle(state.isActive ? Color.primary : Color.secondary)
                context.draw(text, at: CGPoint(x: 16, y: y), anchor: .topLeading)
            }
            if hiddenCount > 0 {
                let text = Text("and \(hiddenCount.formatted()) more")
                    .font(Self.font)
                    .foregroundStyle(Color.secondary)
                context.draw(text, at: CGPoint(x: 16, y: CGFloat(rows.count) * Self.lineHeight), anchor: .topLeading)
            }
        }
        .frame(height: CGFloat(shownLineCount) * Self.lineHeight)
        .accessibilityElement()
        .accessibilityLabel("\(rows.count + hiddenCount) tasks")
    }

    private static func line(_ row: InspectorRow) -> String {
        let state = if let fraction = row.fraction {
            "receiving \(Int((fraction * 100).rounded()))%"
        } else if let failure = row.failure {
            failure
        } else {
            row.state.title
        }
        return [
            column(row.key.title, 6),
            column(row.kind.title, 6),
            column(row.priority.demoTitle, 6),
            column(state, 13),
            demoPad(demoSeconds(row.age), to: 6)
        ].joined(separator: " ")
    }

    /// Cut or padded to `width` characters, left-aligned.
    private static func column(_ text: String, _ width: Int) -> String {
        String(text.prefix(width)).padding(toLength: width, withPad: " ", startingAt: 0)
    }
}

extension ImageRequest.Priority {
    /// Six characters at most, for a column.
    fileprivate var demoTitle: String {
        switch self {
        case .veryLow: "v.low"
        case .low: "low"
        case .normal: "normal"
        case .high: "high"
        case .veryHigh: "v.high"
        }
    }
}

// MARK: - Queues

/// A queue: its slots, what runs and waits, how long work waited, and its
/// limit and switch.
private struct InspectorQueueRow: View {
    let model: ConcurrencyInspectorModel
    let status: ConcurrencyInspectorModel.QueueStatus

    private var isPaused: Bool {
        model.isPaused
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(status.queue.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Menu {
                    Picker("Limit", selection: Binding(get: { status.limit }, set: { model.setLimit($0, for: status.queue) })) {
                        ForEach(ConcurrencyInspectorModel.limitChoices, id: \.self) { limit in
                            Text("\(limit)").tag(limit)
                        }
                    }
                } label: {
                    Text("limit \(status.limit)")
                        .font(.caption.monospacedDigit())
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                Button(model.suspended.contains(status.queue) ? "Resume" : "Suspend") {
                    model.toggleSuspended(status.queue)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .lineLimit(1)
                .fixedSize()
                .disabled(isPaused)
            }
            HStack(spacing: 8) {
                slots
                DemoMonoLabel(counts, tint: .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            (suspension + Text(waits).foregroundStyle(.secondary))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 2)
    }

    private var suspension: Text {
        guard status.isSuspended else {
            return Text(verbatim: "")
        }
        return Text(verbatim: isPaused ? "paused · " : "suspended · ")
            .foregroundStyle(.orange)
            .fontWeight(.semibold)
    }

    /// A square per slot, filled while work runs in it.
    private var slots: some View {
        HStack(spacing: 2) {
            ForEach(0..<min(status.limit, 12), id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < status.running ? (status.isSuspended ? Color.orange : Color.accentColor) : Color.primary.opacity(0.12))
                    .frame(width: 7, height: 10)
            }
        }
    }

    private var counts: String {
        let running = status.inFlight.map { "\($0)" } ?? "\(status.figures.running)"
        let source = status.inFlight == nil ? "*" : ""
        return "\(demoPad(running, to: 2))/\(status.limit)\(source) running · \(demoPad(status.figures.waiting.formatted(), to: 4)) waiting"
    }

    private var waits: String {
        let wait = status.figures.wait
        guard wait.count > 0 else {
            return "nothing has waited"
        }
        return "waited \(demoDuration(wait.average)) avg · \(demoDuration(wait.max)) max · \(wait.count.formatted()) started"
    }
}

/// The queues of every pipeline, a row each.
private struct InspectorPipelinesTable: View {
    let pipelines: [ConcurrencyInspectorModel.PipelineQueues]

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                Text("")
                    .frame(minWidth: 12)
                ForEach(InspectorQueue.allCases, id: \.self) { queue in
                    Text(queue.shortTitle)
                }
            }
            .foregroundStyle(.secondary)
            ForEach(pipelines) { pipeline in
                // The label on a line of its own: the long ones don't fit
                // beside the figures on a phone.
                GridRow {
                    Text(pipeline.label)
                        .lineLimit(1)
                        .gridCellColumns(InspectorQueue.allCases.count + 1)
                        .gridCellAnchor(.leading)
                }
                GridRow {
                    Text("")
                    ForEach(Array(pipeline.queues.enumerated()), id: \.offset) { _, queue in
                        Text("\(queue.inFlightCount.map { "\($0)" } ?? "–")/\(queue.limit)")
                            .foregroundStyle(queue.isSuspended ? .orange : .primary)
                    }
                }
            }
        }
        .font(.system(.caption2, design: .monospaced))
        .lineLimit(1)
    }
}

// MARK: - Stalls

/// A stall: when it started, how long it was, and what each watchdog saw.
private struct InspectorStallRow: View {
    let stall: ConcurrencyInspectorModel.Stall

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(stall.date, format: .dateTime.hour().minute().second().secondFraction(.fractional(2)))
                Spacer()
                Text("\(demoDelay(stall.duration)) stall")
                    .foregroundStyle(stall.duration > 0.1 ? .red : .orange)
            }
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            DemoMonoLabel(detail)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var detail: String {
        let frame = stall.hitch.map { hitch in
            "frame \(demoDelay(hitch.duration)), \(hitch.missedRefreshCount) missed"
        } ?? "no late frame"
        let ping = stall.ping.map { "block waited \(demoDelay($0.duration))" } ?? "no block late"
        return "\(frame) · \(ping)"
    }
}
