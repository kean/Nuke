// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import SwiftUI

/// Demonstrates what the pipeline does when many requests arrive at once: the
/// requests for the same data share one download, and the downloads wait for
/// a data loading slot in the order of their priority.
///
/// ```swift
/// var configuration = ImagePipeline.Configuration()
/// configuration.dataLoadingQueue.maxConcurrentTaskCount = 2
///
/// let task = pipeline.imageTask(with: request)
/// task.priority = .high
/// ```
///
/// Twenty requests for six photos start together, against a queue of two
/// slots and a loader that takes a couple of seconds per photo. The counter
/// comes from the demo's pipeline probe: twenty tasks, six downloads.
///
/// `TaskQueue` doesn't say what is waiting in it, so the screen works the
/// waiting line out itself: a download is running from the moment the
/// pipeline calls `willLoadData`, which it does once the download has a slot,
/// and the downloads that haven't started are in the order the queue's rule
/// gives them (see ``PriorityCoalescingDemoModel``). The order the downloads
/// start in is the check on it.
struct PriorityCoalescingDemo: View {
    @StateObject private var model = PriorityCoalescingDemoModel()
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        // The queue above the requests, except on a phone on its side, which
        // has the width for both and not the height.
        let isSideBySide = verticalSizeClass == .compact
        let layout = isSideBySide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        let stage = PriorityCoalescingStage(model: model)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        layout {
            if isSideBySide {
                ScrollView {
                    stage
                }
                .frame(maxWidth: 400)
            } else {
                stage
            }
            Divider()
            PriorityCoalescingList(model: model)
        }
        .background(Color(.systemGroupedBackground))
        .task {
            model.runIfNeeded()
            while !Task.isCancelled {
                model.sampleFigures()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .onDisappear { model.cancelAll() }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Priority & Coalescing",
        "Twenty requests for six photos start at once. The pipeline gives the requests for one photo a single download, and the downloads wait for a slot in the data loading queue in the order of their priority. The letters at the top are the downloads: running, waiting in the order they will start, and done.",
        code: """
        var configuration = ImagePipeline.Configuration()
        configuration.dataLoadingQueue.maxConcurrentTaskCount = 2
        let pipeline = ImagePipeline(configuration: configuration)

        let task = pipeline.imageTask(with: request)
        task.priority = .high
        """,
        points: [
            .init("Try it", "The screen opens on a run. Pick a priority on a row of a download that is waiting, and the download moves in the line. Hold stops the queue, so the line can be rearranged before anything starts. Cancel stops every request, a swipe stops one, and Run starts over."),
            .init("Coalescing", "The pipeline keys a download by its URL and not by the processors, so the original, the square, and the circle of photo A share one download. Requests that are exactly the same, like #1 and #18, share the decoding and the processing too. Every row says whose download it waits on."),
            .init("The counter", "From the demo's pipeline probe. A task is counted when the pipeline creates it, a download when the pipeline asks its delegate for a data loader, which it does once per download, after coalescing. Images per download divides the images that came from the network by the downloads that finished."),
            .init("The queue", "`dataLoadingQueue` runs six downloads at a time by default. This screen gives it two, and a loader that takes about two seconds per photo, so the waiting shows. `maxConcurrentTaskCount` can change at any time, and a higher limit starts the next downloads at once. `isSuspended`, the Hold button, keeps the queue from starting any more."),
            .init("Priority", "Priority orders only the work that is waiting: the highest first, and first come, first served within a priority. A download whose priority goes up joins the back of its new priority, and one whose priority goes down joins the front of its new one. Once a download has a slot, its priority changes nothing."),
            .init("A download's priority", "A download runs at the highest priority of the requests that share it. #17 asks for `.high`, so download E waits ahead of C and D, which were queued first. Lower #17 to `.normal` and E stays at the front, where the queue puts work whose priority drops. Lowering another row of E changes nothing."),
            .init("What the screen sees", "`TaskQueue` doesn't say what is waiting in it. A download shows as running once the pipeline calls the delegate's `willLoadData`, which it does after the download gets a slot. The waiting line is the queue's rule applied to the requests on screen, and the order the downloads start in is the check on it."),
            .init("skipDataLoadingQueue", "#20 has the option. The documentation says a request with it gets a download of its own, which would start at once. The pipeline keys downloads by URL and ignores the options, so #20 joins download F and waits in the queue with it – Hold makes it plain – and the counter still reads six downloads. A request with the option that is the first for its URL does skip the queue."),
            .init("Cancellation", "Cancelling a request cancels its download only when no other request shares it. Swipe away the rows of one photo, and the download stops with the last one. The slot comes back when the loader calls `completion`, which this screen's loader does for every load, a cancelled one included."),
            .init("Fresh downloads", "Every run adds a `run` query item to the URLs, so it misses what the earlier runs cached and downloads again, and it never resumes a download that an earlier run cancelled. The caches stay on: the pipeline has a memory cache and a `DataCache` of its own, emptied when the screen opens.")
        ]
    )
}

// MARK: - Stage

/// The counter, the downloads by where they are in the queue, and the
/// controls.
private struct PriorityCoalescingStage: View {
    @ObservedObject var model: PriorityCoalescingDemoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            counter
            QueueView(model: model)
            controls
        }
    }

    private var counter: some View {
        let figures = model.figures
        let perDownload = figures.imagesPerDownload.map { String(format: "%.1f", $0) } ?? "–"
        let inFlight = figures.inFlightCount.map(String.init) ?? "–"
        return VStack(alignment: .leading, spacing: 2) {
            Text("tasks \(demoPad("\(figures.taskCount)", to: 2)) · downloads \(demoPad("\(figures.downloadCount)", to: 2))")
                .font(.system(.title3, design: .monospaced).weight(.semibold))
            DemoMonoLabel("\(perDownload) images per download · in flight \(inFlight) of \(figures.slotCount)")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// Without the icons where the row doesn't fit with them: beside the
    /// requests on a phone on its side.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            controlRow
            controlRow
                .labelStyle(.titleOnly)
        }
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            Button("Run", systemImage: "arrow.clockwise") { model.run() }
            Button("Cancel", systemImage: "xmark") { model.cancelAll() }
                .disabled(!model.isBusy)
            Spacer(minLength: 8)
            Toggle(isOn: $model.isHeld) {
                Label("Hold", systemImage: "pause")
            }
            .toggleStyle(.button)
            Menu {
                Picker("Slots", selection: $model.slotCount) {
                    ForEach(1...6, id: \.self) { count in
                        Text(demoCount(count, "slot")).tag(count)
                    }
                }
            } label: {
                Text(demoCount(model.slotCount, "slot"))
                    .monospacedDigit()
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// The downloads in three lanes: holding a slot, waiting for one in the
/// order the queue will start them, and done.
private struct QueueView: View {
    @ObservedObject var model: PriorityCoalescingDemoModel
    /// A download that gets a slot slides up from the waiting lane. One that
    /// ends fades into the done lane instead: sliding, it would cross the
    /// waiting lane while the queue moves up.
    @Namespace private var lanes

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                label("running")
                HStack(spacing: 4) {
                    ForEach(model.running) { download in
                        chip(download)
                    }
                    // The free slots, so the limit is there to see.
                    ForEach(0..<max(0, model.slotCount - model.running.count), id: \.self) { _ in
                        FreeSlot(isHeld: model.isHeld)
                    }
                }
            }
            GridRow {
                label("waiting")
                lane(model.waiting, slides: true)
            }
            GridRow {
                label("done")
                lane(model.finished, slides: false)
            }
        }
        .animation(.snappy, value: model.running.map(\.id))
        .animation(.snappy, value: model.waiting.map(\.id))
        .animation(.snappy, value: model.finished.map(\.id))
        .animation(.snappy, value: model.slotCount)
    }

    private func chip(_ download: DownloadModel) -> some View {
        DownloadChip(download: download)
            .matchedGeometryEffect(id: download.id, in: lanes)
    }

    @ViewBuilder
    private func laneChip(_ download: DownloadModel, slides: Bool) -> some View {
        if slides {
            chip(download)
        } else {
            DownloadChip(download: download)
        }
    }

    private func label(_ text: String) -> some View {
        DemoMonoLabel(text)
            .gridColumnAlignment(.leading)
    }

    private func lane(_ downloads: [DownloadModel], slides: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(downloads) { download in
                laneChip(download, slides: slides)
            }
            if downloads.isEmpty {
                // Holds the height of the row.
                FreeSlot(isHeld: false)
                    .hidden()
            }
        }
    }
}

/// A download: its letter, the progress while it runs, and an arrow for a
/// priority other than `.normal`.
private struct DownloadChip: View {
    @ObservedObject var download: DownloadModel

    var body: some View {
        HStack(spacing: 1) {
            Text(download.letter)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
            if let mark = download.mark {
                Text(mark)
                    .font(.caption2.weight(.bold))
            }
        }
        .frame(width: 40, height: 28)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                download.color.opacity(0.3)
                    .frame(width: proxy.size.width * (download.phase == .running ? download.progress : 0))
            }
        }
        .background(download.color.opacity(download.phase == .waiting || download.phase == .running ? 0.12 : 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(download.color.opacity(0.6), lineWidth: 1)
        }
        .foregroundStyle(download.color)
        .opacity(download.phase == .waiting || download.phase == .running ? 1 : 0.6)
    }
}

private struct FreeSlot: View {
    let isHeld: Bool

    var body: some View {
        Image(systemName: isHeld ? "pause" : "minus")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(width: 40, height: 28)
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.tertiary)
            }
    }
}

// MARK: - Requests

/// The requests, by the download they wait on.
private struct PriorityCoalescingList: View {
    @ObservedObject var model: PriorityCoalescingDemoModel

    var body: some View {
        List {
            ForEach(model.downloads) { download in
                Section {
                    ForEach(download.rows) { row in
                        RequestRow(row: row, download: download, model: model)
                    }
                } header: {
                    DownloadHeader(download: download)
                } footer: {
                    if let row = download.rows.first(where: \.skipsQueue) {
                        Text("#\(row.number) has `.skipDataLoadingQueue`, which the documentation says gives it a download of its own. The pipeline keys downloads by URL, so it joins \(download.letter)'s download and waits in the queue with it.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
    }
}

private struct DownloadHeader: View {
    @ObservedObject var download: DownloadModel

    var body: some View {
        HStack(spacing: 10) {
            DownloadChip(download: download)
            VStack(alignment: .leading, spacing: 1) {
                Text("Download \(download.letter)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                DemoMonoLabel(download.status)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                DemoMonoLabel(download.priority.demoName, tint: download.priority == .normal ? nil : Color(.label))
                if let row = download.priorityRow {
                    DemoMonoLabel("from #\(row)")
                }
            }
        }
        .textCase(nil)
        .padding(.top, 4)
    }
}

private struct RequestRow: View {
    @ObservedObject var row: TaskRowModel
    @ObservedObject var download: DownloadModel
    let model: PriorityCoalescingDemoModel

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("#\(row.number)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(row.variant.title)
                }
                .font(.subheadline)
                if row.skipsQueue {
                    DemoMonoLabel(".skipDataLoadingQueue", tint: .orange)
                }
                DemoMonoLabel(status, tint: statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            priorityMenu
        }
        .swipeActions(edge: .trailing) {
            if row.isActive {
                Button("Cancel") { model.cancel(row) }
                    .tint(.red)
            }
        }
    }

    private var thumbnail: some View {
        download.color.opacity(0.12)
            .frame(width: 36, height: 36)
            .overlay {
                if case .succeeded(let image, _) = row.phase {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(download.letter)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(download.color)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var priorityMenu: some View {
        Menu {
            Picker("Priority", selection: Binding(get: { row.priority }, set: { model.setPriority($0, for: row) })) {
                ForEach(ImageRequest.Priority.demoAllCases, id: \.self) { priority in
                    Text(priority.demoName).tag(priority)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(row.priority.demoName)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .font(.caption.monospaced())
        }
        .disabled(!row.isActive)
    }

    /// What the request is doing, and whose download it waits on.
    private var status: String {
        let phase: String
        switch row.phase {
        case .active:
            switch download.phase {
            case .waiting: phase = "waiting"
            case .running: phase = "\(Int(download.progress * 100))%"
            case .finished, .failed, .cancelled: phase = "finishing"
            }
        case .succeeded(_, let duration):
            phase = "done" + (duration.map { " " + seconds($0) } ?? "")
        case .cancelled:
            return "cancelled"
        case .failed(let reason):
            return "failed · \(reason)"
        }
        guard let owner = row.downloadOwner else {
            return phase
        }
        return phase + " · " + (owner == row.number ? "own download" : "shares #\(owner)'s")
    }

    private var statusColor: Color? {
        switch row.phase {
        case .active: download.phase == .running ? Color.blue : nil
        case .succeeded: .green
        case .cancelled: .orange
        case .failed: .red
        }
    }
}

// MARK: - Model

/// Starts the requests, and keeps the picture of the queue that the screen
/// draws.
///
/// The waiting line follows the rule `TaskQueue` orders its work by, applied
/// to what the screen asked for:
///
/// - Downloads wait in one line per priority, and the queue takes the next
///   one from the highest priority that has any.
/// - A download joins the back of its line.
/// - A download whose priority goes up moves to the back of its new line; one
///   whose priority goes down, to the front of its new line.
/// - A download is queued at `.normal` and moved to its priority right away –
///   so one created below `.normal` goes to the front of its line.
/// - A download runs at the highest priority of the requests still waiting
///   on it, and a download left with none is cancelled.
///
/// A download leaves the line when the pipeline reports that it started. The
/// queue starts work the moment it is queued if a slot is free, before its
/// priority is applied, which is how A and B start first. The running
/// downloads are in the order they started.
@MainActor
private final class PriorityCoalescingDemoModel: ObservableObject {
    /// What the probe counted since the run started.
    struct Figures: Equatable {
        var taskCount = 0
        var downloadCount = 0
        /// The images that came from the network, per finished download.
        var imagesPerDownload: Double?
        var inFlightCount: Int?
        var slotCount = 0
    }

    /// The six photos, one download each.
    private static var photos: [URL] {
        Array(DemoImages.photos.prefix(6))
    }

    /// The requests of a run, in the order they start: every photo, then
    /// every photo again as a square, so that the first six start the
    /// downloads and the rest join them.
    private static let plan: [PlannedRequest] = {
        var plan = (0..<6).map { PlannedRequest(download: $0, variant: .original) }
        plan += (0..<6).map { PlannedRequest(download: $0, variant: .square) }
        plan += (0..<4).map { PlannedRequest(download: $0, variant: .circle) }
        // Pulls download E ahead of C and D.
        plan.append(PlannedRequest(download: 4, variant: .circle, priority: .high))
        // The same request as #1.
        plan.append(PlannedRequest(download: 0, variant: .original))
        plan.append(PlannedRequest(download: 2, variant: .blurred))
        // Asks to skip the queue, and joins F's download instead.
        plan.append(PlannedRequest(download: 5, variant: .original, skipsQueue: true))
        return plan
    }()

    @Published private(set) var downloads: [DownloadModel] = []
    /// The downloads holding a slot, in the order they started.
    @Published private(set) var running: [DownloadModel] = []
    /// The downloads waiting for a slot, in the order the queue will start them.
    @Published private(set) var waiting: [DownloadModel] = []
    /// The downloads that ended, in the order they did.
    @Published private(set) var finished: [DownloadModel] = []
    /// Whether any request is still waiting or loading.
    @Published private(set) var isBusy = false
    @Published private(set) var figures = Figures()

    /// Suspends the data loading queue.
    @Published var isHeld = false {
        didSet { queue.isSuspended = isHeld }
    }
    /// The data loading queue's limit.
    @Published var slotCount = 2 {
        didSet { queue.maxConcurrentTaskCount = slotCount }
    }

    private let pipeline: ImagePipeline
    private let queue: TaskQueue
    private var rows: [TaskRowModel] = []
    /// The waiting downloads, a line per priority, by the raw value of the
    /// priority.
    private var lines: [[DownloadModel]] = []
    /// The probe's figures when the run started.
    private var baseline = DemoPipelineDiagnostics()
    private var isStarted = false

    init() {
        let queue = TaskQueue(maxConcurrentTaskCount: 2)
        var configuration = ImagePipeline.Configuration.withDataCache(name: "com.github.kean.NukeDemo.PriorityAndCoalescing")
        // Every photo in 16 chunks, 140 ms apart: about two seconds each,
        // whatever its size.
        configuration.dataLoader = PacedDataLoader(pace: .chunks(16, interval: .milliseconds(140)))
        configuration.dataLoadingQueue = queue
        configuration.imageCache = ImageCache()
        // Every task finishes with a record of whose download it waited on,
        // and how long the download waited for its slot.
        configuration.isDiagnosticsEnabled = true
        configuration.dataCache?.removeAll()

        // The probe reports `willLoadData` on the pipeline's actor, once the
        // download has a slot.
        let relay = Relay()
        self.queue = queue
        self.pipeline = DemoPipelineProbe.makePipeline("Priority & Coalescing", configuration: configuration, onEvent: { event in
            guard case .willLoadData(let urlRequest) = event.kind, let url = urlRequest.url else { return }
            Task { @MainActor in relay.model?.downloadDidStart(url) }
        })
        relay.model = self
    }

    func runIfNeeded() {
        guard !isStarted else { return }
        isStarted = true
        run()
    }

    // MARK: Running

    func run() {
        cancelAll()

        // A new URL for every run, so that nothing an earlier run cached or
        // left to resume is found.
        let runID = String(format: "%04x", UInt16.random(in: .min ... .max))
        let downloads = Self.photos.enumerated().map { index, url in
            DownloadModel(id: index, url: url.appending(queryItems: [URLQueryItem(name: "run", value: runID)]))
        }
        rows = Self.plan.enumerated().map { index, plan in
            let download = downloads[plan.download]
            let row = TaskRowModel(number: index + 1, plan: plan, download: download)
            download.rows.append(row)
            return row
        }
        self.downloads = downloads
        running = []
        finished = []
        lines = Array(repeating: [], count: ImageRequest.Priority.demoAllCases.count)
        baseline = DemoPipelineProbe.diagnostics(for: pipeline) ?? DemoPipelineDiagnostics()

        for row in rows {
            let task = pipeline.imageTask(with: row.request)
            row.task = task
            observe(task, of: row)
            if row.download.rows.first === row {
                enqueue(row.download, priority: row.priority)
            } else {
                updatePriority(of: row.download)
            }
        }
        publishQueue()
        sampleFigures()
    }

    func cancelAll() {
        for row in rows where row.isActive {
            cancel(row)
        }
    }

    func cancel(_ row: TaskRowModel) {
        guard row.isActive else { return }
        row.task?.cancel()
        row.phase = .cancelled
        updatePriority(of: row.download)
        publishQueue()
    }

    func setPriority(_ priority: ImageRequest.Priority, for row: TaskRowModel) {
        guard row.isActive, row.priority != priority else { return }
        row.priority = priority
        row.task?.priority = priority
        updatePriority(of: row.download)
        publishQueue()
    }

    private func observe(_ task: ImageTask, of row: TaskRowModel) {
        Task { [weak self, weak row] in
            for await event in task.events {
                guard let self, let row else { return }
                switch event {
                case .progress(let progress):
                    // Every request that shares the download gets the same.
                    if row.download.phase == .running {
                        row.download.progress = Double(progress.fraction)
                    }
                case .preview:
                    break
                case .finished(let result):
                    self.didFinish(row, task: task, result: result)
                }
            }
        }
    }

    private func didFinish(_ row: TaskRowModel, task: ImageTask, result: Result<ImageResponse, ImagePipeline.Error>) {
        // A request of an earlier run, cancelled when this one started.
        guard rows.contains(where: { $0 === row }) else { return }
        let metrics = task.metrics
        switch result {
        case .success(let response):
            row.phase = .succeeded(response.image, duration: metrics?.duration)
            row.readOwner(from: metrics, rows: rows)
            finish(row.download, metrics: metrics, isFailure: false)
        case .failure(.cancelled):
            guard row.isActive else { return }
            row.phase = .cancelled
            updatePriority(of: row.download)
        case .failure(let error):
            row.phase = .failed(error.demoSummary)
            finish(row.download, metrics: metrics, isFailure: true)
        }
        publishQueue()
    }

    /// The pipeline started a download: it has a slot.
    private func downloadDidStart(_ url: URL) {
        // An earlier run's download is a different URL.
        guard let download = downloads.first(where: { $0.url == url }), download.phase == .waiting else { return }
        removeFromLine(download)
        download.phase = .running
        running.append(download)
        publishQueue()
    }

    /// The first request of a download to end ends the download: its data
    /// has arrived, or failed to.
    private func finish(_ download: DownloadModel, metrics: ImageTask.Metrics?, isFailure: Bool) {
        guard download.phase == .waiting || download.phase == .running else { return }
        removeFromLine(download)
        running.removeAll { $0 === download }
        download.phase = isFailure ? .failed : .finished
        download.record = metrics.flatMap { DownloadModel.Record($0) }
        finished.append(download)
    }

    // MARK: The Queue

    private func enqueue(_ download: DownloadModel, priority: ImageRequest.Priority) {
        lines[ImageRequest.Priority.normal.rawValue].append(download)
        download.priority = .normal
        move(download, to: priority)
        updatePriorityRow(of: download)
    }

    /// The highest priority of the requests still waiting on the download,
    /// which is the priority the pipeline gives the download.
    private func updatePriority(of download: DownloadModel) {
        let active = download.rows.filter(\.isActive)
        guard let priority = active.map(\.priority).max() else {
            // No request is left to share it: the pipeline cancels it.
            if download.phase == .waiting || download.phase == .running {
                removeFromLine(download)
                running.removeAll { $0 === download }
                download.phase = .cancelled
                finished.append(download)
            }
            return
        }
        move(download, to: priority)
        updatePriorityRow(of: download)
    }

    private func updatePriorityRow(of download: DownloadModel) {
        let active = download.rows.filter(\.isActive)
        download.priorityRow = download.priority == .normal ? nil : active.first { $0.priority == download.priority }?.number
    }

    private func move(_ download: DownloadModel, to priority: ImageRequest.Priority) {
        let oldPriority = download.priority
        guard priority != oldPriority else { return }
        download.priority = priority
        // Only a waiting download moves; a running one keeps its slot.
        guard let index = lines[oldPriority.rawValue].firstIndex(where: { $0 === download }) else { return }
        lines[oldPriority.rawValue].remove(at: index)
        if priority < oldPriority {
            lines[priority.rawValue].insert(download, at: 0)
        } else {
            lines[priority.rawValue].append(download)
        }
    }

    private func removeFromLine(_ download: DownloadModel) {
        for index in lines.indices {
            lines[index].removeAll { $0 === download }
        }
    }

    private func publishQueue() {
        let waiting = Array(lines.reversed().joined())
        for (index, download) in waiting.enumerated() where download.place != index + 1 {
            download.place = index + 1
        }
        // Every run makes new downloads with the same ids.
        if !waiting.elementsEqual(self.waiting, by: ===) {
            self.waiting = waiting
        }
        isBusy = rows.contains(where: \.isActive)
    }

    // MARK: Figures

    func sampleFigures() {
        guard let current = DemoPipelineProbe.diagnostics(for: pipeline) else { return }
        let completed = current.completedDownloadCount - baseline.completedDownloadCount
        let images = current.networkResponseCount - baseline.networkResponseCount
        let figures = Figures(
            taskCount: current.createdTaskCount - baseline.createdTaskCount,
            downloadCount: current.downloadCount - baseline.downloadCount,
            imagesPerDownload: completed > 0 ? Double(images) / Double(completed) : nil,
            inFlightCount: current.dataLoadingQueue.inFlightCount,
            slotCount: current.dataLoadingQueue.limit
        )
        if figures != self.figures {
            self.figures = figures
        }
    }

    private typealias Relay = DemoRelay<PriorityCoalescingDemoModel>
}

/// A request of the plan.
private struct PlannedRequest {
    /// The index of the photo.
    let download: Int
    let variant: RequestVariant
    var priority: ImageRequest.Priority = .normal
    var skipsQueue = false
}

/// What a request makes of its photo. Every variant downloads the same data.
private enum RequestVariant {
    case original
    case square
    case circle
    case blurred

    var title: String {
        switch self {
        case .original: "original"
        case .square: "square"
        case .circle: "circle"
        case .blurred: "blurred"
        }
    }

    var processors: [any ImageProcessing] {
        let square = ImageProcessors.Resize(size: CGSize(width: 64, height: 64), crop: true)
        switch self {
        case .original: return []
        case .square: return [square]
        case .circle: return [square, ImageProcessors.Circle()]
        case .blurred: return [square, ImageProcessors.GaussianBlur(radius: 3)]
        }
    }
}

/// One of the six downloads of a run, and the requests that wait on it.
@MainActor
private final class DownloadModel: ObservableObject, Identifiable {
    enum Phase {
        case waiting
        case running
        case finished
        case failed
        case cancelled
    }

    /// What the record of a finished request says about its download.
    struct Record {
        /// The time the download waited for a slot.
        let queueWait: TimeInterval?
        let byteCount: Int64?
        /// The priority of the download over time, the changes only.
        let priorities: [ImageRequest.Priority]

        init?(_ metrics: ImageTask.Metrics) {
            guard let job = metrics.jobs.first(where: { $0.kind == .fetchOriginalData }) else { return nil }
            let download = job.stages.first { $0.kind == .download }
            queueWait = download?.queueWait
            byteCount = download?.bytes
            var priorities: [ImageRequest.Priority] = []
            for change in job.priorityHistory where change.priority != priorities.last {
                priorities.append(change.priority)
            }
            self.priorities = priorities
        }
    }

    let id: Int
    let url: URL
    fileprivate(set) var rows: [TaskRowModel] = []
    @Published fileprivate(set) var phase: Phase = .waiting
    @Published fileprivate(set) var progress: Double = 0
    @Published fileprivate(set) var priority: ImageRequest.Priority = .normal
    /// The request the download takes its priority from, when it isn't
    /// `.normal`.
    @Published fileprivate(set) var priorityRow: Int?
    /// The place in the waiting line, from 1.
    @Published fileprivate(set) var place = 0
    @Published fileprivate(set) var record: Record?

    init(id: Int, url: URL) {
        self.id = id
        self.url = url
    }

    var letter: String {
        String(Character(Unicode.Scalar(UInt8(ascii: "A") + UInt8(id))))
    }

    var color: Color {
        [Color.blue, .orange, .green, .purple, .pink, .teal][id % 6]
    }

    /// A cross for a download that didn't finish, or an arrow for each step
    /// its priority is above or below `.normal`.
    var mark: String? {
        if phase == .cancelled || phase == .failed {
            return "×"
        }
        return switch priority {
        case .veryLow: "↓↓"
        case .low: "↓"
        case .normal: nil
        case .high: "↑"
        case .veryHigh: "↑↑"
        }
    }

    var status: String {
        let count = "\(rows.count) requests"
        switch phase {
        case .waiting:
            return "\(place == 1 ? "next" : ordinal(place)) in line · \(count)"
        case .running:
            return "downloading \(Int(progress * 100))% · \(count)"
        case .finished:
            guard let record else { return "done · \(count)" }
            var parts = ["waited " + (record.queueWait.map(seconds) ?? "–")]
            if let byteCount = record.byteCount {
                parts.append(demoByteCount(byteCount))
            }
            if record.priorities.count > 1 {
                parts.append(record.priorities.map(\.demoName).joined(separator: "→"))
            }
            return parts.joined(separator: " · ")
        case .failed:
            return "failed"
        case .cancelled:
            return "cancelled"
        }
    }
}

/// A request of the run.
@MainActor
private final class TaskRowModel: ObservableObject, Identifiable {
    enum Phase {
        case active
        case succeeded(UIImage, duration: TimeInterval?)
        case cancelled
        case failed(String)
    }

    let number: Int
    let variant: RequestVariant
    let skipsQueue: Bool
    let request: ImageRequest
    unowned let download: DownloadModel
    var task: ImageTask?

    @Published fileprivate(set) var priority: ImageRequest.Priority
    @Published fileprivate(set) var phase: Phase = .active
    /// The request that started the download this one waits on: the first
    /// request for the photo, until the task's record says otherwise.
    @Published fileprivate(set) var downloadOwner: Int?

    nonisolated var id: Int { number }

    /// Started, and neither finished nor cancelled.
    var isActive: Bool {
        guard task != nil, case .active = phase else { return false }
        return true
    }

    init(number: Int, plan: PlannedRequest, download: DownloadModel) {
        self.number = number
        self.variant = plan.variant
        self.skipsQueue = plan.skipsQueue
        self.priority = plan.priority
        self.download = download
        self.downloadOwner = download.rows.first?.number ?? number
        var request = ImageRequest(url: download.url, processors: plan.variant.processors, priority: plan.priority)
        if plan.skipsQueue {
            request.options.insert(.skipDataLoadingQueue)
        }
        self.request = request
    }

    /// Reads whose download the request waited on from its record.
    fileprivate func readOwner(from metrics: ImageTask.Metrics?, rows: [TaskRowModel]) {
        guard let job = metrics?.jobs.first(where: { $0.kind == .fetchOriginalData }) else { return }
        downloadOwner = rows.first { $0.task?.taskId == job.createdByTaskID }?.number
    }
}

// MARK: - Helpers

private func seconds(_ interval: TimeInterval) -> String {
    String(format: "%.1f s", interval)
}

/// "2nd", "3rd", "4th" – the places a line of six has after the first.
private func ordinal(_ number: Int) -> String {
    let suffix = switch number % 10 {
    case 1 where number % 100 != 11: "st"
    case 2 where number % 100 != 12: "nd"
    case 3 where number % 100 != 13: "rd"
    default: "th"
    }
    return "\(number)\(suffix)"
}
