// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import SwiftUI

/// Demonstrates ``DataLoading``: three loaders of the app's own load the same
/// request, and the screen lists every call between the pipeline and the
/// loader.
///
/// ```swift
/// var configuration = ImagePipeline.Configuration()
/// configuration.dataLoader = ThrottledDataLoader()
/// ```
///
/// The calls come from the demo's pipeline probe, which stands between the
/// pipeline and the loader: the chunks, the pipeline's cancel, and the one
/// `completion`. ``ThrottledDataLoader`` follows the documentation of
/// ``DataLoading`` and calls nothing after a cancel, and the pipeline frees a
/// load's data loading slot only in `completion`, so a load cancelled
/// halfway keeps its slot, and its pipeline, for good. The screen shows that
/// rather than working around it: every run gets a new pipeline, and the
/// probe's figures say what the earlier ones still hold.
/// ``BundleDataLoader`` and ``FailingDataLoader`` call `completion` after a
/// cancel, which frees the slot.
struct CustomDataLoaderDemo: View {
    @StateObject private var model = CustomDataLoaderDemoModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        // The load above the calls, except on a phone on its side, which has
        // the width for both and not the height.
        let isSideBySide = verticalSizeClass == .compact
        let layout = isSideBySide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        let stage = CustomDataLoaderStage(model: model, isWide: horizontalSizeClass == .regular && !isSideBySide)
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
            CustomDataLoaderList(model: model)
        }
        .background(Color(.systemGroupedBackground))
        .task {
            model.runIfNeeded()
            while !Task.isCancelled {
                model.sampleFigures()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .onDisappear { model.cancel() }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Custom Data Loader",
        "A pipeline loads data with whatever `DataLoading` it's given. Here, three loaders of the app's own load the same request, a 1024×772 WebP, on a new pipeline each run, and the screen lists every call between the pipeline and the loader: a `didReceiveData` for each chunk, the pipeline's `cancel`, and the one `completion`.",
        code: """
        // The one method a loader implements
        func loadData(
            with request: URLRequest,
            didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
            completion: @escaping @Sendable (Error?) -> Void
        ) -> any Cancellable

        // One loader for every request…
        var configuration = ImagePipeline.Configuration()
        configuration.dataLoader = ThrottledDataLoader()

        // …or one per request, picked by the delegate
        func dataLoader(for request: ImageRequest, pipeline: ImagePipeline) -> any DataLoading {
            bundleLoader.canLoad(request) ? bundleLoader : pipeline.configuration.dataLoader
        }
        """,
        points: [
            .init("Try it", "Picking a loader loads the image with it, and Run loads it again. Cancel a Throttled load partway, then a Bundle one, and compare what follows the cancel: the calls, and the slots. The Code section at the bottom has the loader that is picked."),
            .init("didReceiveData", "Call it for every chunk as it arrives, with only the new bytes – the pipeline appends them – and with the response. The pipeline reports progress once per chunk, and with progressive decoding on, it decodes previews from them (see Progressive Decoding)."),
            .init("The response", "Progress is measured against its `expectedContentLength`. A cancelled download resumes only if its response is an `HTTPURLResponse` with `Accept-Ranges` and a validator (see Resumable Downloads). The bundle loader's plain `URLResponse` has neither, so its loads start over."),
            .init("completion", "Call it exactly once, with `nil` or the error, and nothing after it. The pipeline fails the task with `ImagePipeline.Error.dataLoadingFailed`, which carries the loader's error, so an app can tell a server error from a lost connection."),
            .init("Cancel", "When the last task that needs the data is cancelled, the pipeline calls `cancel()` on what `loadData` returned. The documentation asks a loader to call neither closure after that, and ThrottledDataLoader doesn't. But the pipeline frees the load's data loading slot only when `completion` is called, so today such a loader keeps the slot of every load cancelled partway, and the pipeline the load belongs to, for as long as the app runs. The slots figure and the earlier runs row show both."),
            .init("Completing after a cancel", "BundleDataLoader and FailingDataLoader call `completion` with `URLError(.cancelled)` after a cancel, as `DataLoader` does: `URLSession` reports a cancelled task as completed. The slot is free at once, and the call reaches nothing of the app's, because the pipeline let go of the task when it cancelled the load."),
            .init("Throttled", "`ThrottledDataLoader` downloads the image with a `URLSession` of its own, then hands it on 8 KB at a time, 150 ms apart, so that a fast connection looks slow. Progressive Decoding uses it too."),
            .init("Bundle", "`BundleDataLoader` answers the URLs it has a file for from the app bundle, 4 KB at a time, 200 ms apart; an app would hand the file on in one chunk. The pipeline's delegate sends it those requests and leaves the rest to the configured loader. Its file for this URL is the demo's own 1024×772 WebP, the one that stands in for the photo offline, so the picture says which loader answered."),
            .init("Failing", "`FailingDataLoader` fails every request with the error `DataLoader` or `URLSession` would report: a 500 before any data, or a connection lost a third of the way into the body."),
            .init("Installing a loader", "`configuration.dataLoader` loads every request of the pipeline. The delegate's `dataLoader(for:pipeline:)` picks a loader per request; the pipeline asks it once per download, after coalescing, when a data loading slot is free."),
            .init("A pipeline per run", "Every run loads the image on a new pipeline, so that a slot an earlier run keeps doesn't hold this one up. The pipelines share a memory cache and a `DataCache`, and the request has `.reloadIgnoringCachedData`: the caches are written, not read, and every run goes to the loader. The calls come from the demo's pipeline probe, which passes each one on as it is."),
            .init("Offline and network conditions", "Offline, the fixture loader answers ThrottledDataLoader's requests at the same pace, and it completes after a cancel, so no slot is kept. The other two loaders never go to the network and keep their requests. With Network Conditions on, every load goes through the Lab's rig, which completes a cancelled load itself, whatever the loader does.")
        ]
    )
}

// MARK: - Stage

/// The picker, the image, the figures of the run, the timeline, and the
/// controls.
private struct CustomDataLoaderStage: View {
    @ObservedObject var model: CustomDataLoaderDemoModel
    /// Gives the image more room, where there is more.
    let isWide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Loader", selection: $model.choice) {
                ForEach(LoaderChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            caption

            HStack(alignment: .top, spacing: 12) {
                // A set height: in the stage's stack, a view that keeps its
                // aspect ratio is the first to give up room.
                let width: CGFloat = isWide ? 240 : 132
                preview
                    .frame(width: width, height: (width * 772 / 1024).rounded())
                RunFigures(run: model.run, figures: model.figures)
            }
            if let run = model.run {
                CallTimeline(run: run)
            }
            controls
        }
    }

    /// The loader and where it is installed, and for the failing one, how it
    /// fails.
    private var caption: some View {
        HStack(spacing: 8) {
            Text("\(Text(model.choice.typeName).fontWeight(.semibold)) \(Text(model.choice.installation).foregroundStyle(.secondary))")
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if model.choice == .failing {
                Spacer(minLength: 0)
                Menu {
                    Picker("Failure", selection: $model.failure) {
                        ForEach(FailingDataLoader.Failure.allCases) { failure in
                            Text(failure.title).tag(failure)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(model.failure.title)
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                    }
                    .font(.caption.weight(.medium))
                }
                .fixedSize()
            }
        }
        .frame(minHeight: 24)
    }

    private var preview: some View {
        Color(.secondarySystemGroupedBackground)
            .overlay {
                let run = model.run
                if let image = run?.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else if let run, case .failed = run.outcome {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.red)
                } else if let run, case .cancelled = run.outcome {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                } else if let fraction = run?.progress?.fraction, fraction > 0 {
                    Text("\(Int(fraction * 100))%")
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Without the icons where the row doesn't fit with them: beside the list
    /// on a phone on its side.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            controlRow
            controlRow
                .labelStyle(.titleOnly)
        }
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            Button("Run", systemImage: "arrow.clockwise") { model.startRun() }
            Button("Cancel", systemImage: "xmark") { model.cancel() }
                .disabled(!(model.run?.isLoading ?? false))
            Spacer(minLength: 0)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// What the run's loader did, what the task came to, and the slots its
/// pipeline holds.
private struct RunFigures: View {
    let run: CustomDataLoaderDemoModel.Run?
    let figures: CustomDataLoaderDemoModel.Figures

    var body: some View {
        // Live while a cancelled load hasn't completed: the wait grows.
        TimelineView(.animation(minimumInterval: 0.1, paused: !(run?.isAwaitingCompletion ?? false))) { _ in
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                row("loader", run?.loader?.shortTitle ?? "–")
                row("response", response)
                row("chunks", chunks)
                let completion = completion
                row("completion", completion.text, tint: completion.tint)
                let task = task
                row("task", task.text, tint: task.tint)
                let slots = slots
                row("slots", slots.text, tint: slots.tint)
            }
        }
    }

    private var response: String {
        guard let run else { return "–" }
        guard let response = run.response else {
            return run.completion != nil ? "none" : "–"
        }
        let size = response.expectedContentLength > 0 ? demoByteCount(response.expectedContentLength) : "no length"
        if let response = response as? HTTPURLResponse {
            return "\(response.statusCode) · \(size)"
        }
        return "URLResponse · \(size)"
    }

    private var chunks: String {
        guard let run else { return "–" }
        let chunks = run.chunks
        guard let last = chunks.last else { return "0" }
        return "\(chunks.count) · \(demoByteCount(last.total))"
    }

    private var completion: (text: String, tint: Color?) {
        guard let run else { return ("–", nil) }
        if let completion = run.completion {
            let name = demoShortErrorName(completion.error)
            if let cancel = run.cancel {
                return ("\(name) · \(demoDelay(completion.time - cancel.time))", .green)
            }
            return ("\(name) · \(demoTime(completion.time))", completion.error == nil ? nil : .red)
        }
        if let cancel = run.cancel {
            return ("not called · \(demoDelay(run.elapsed - cancel.time))", .orange)
        }
        return ("–", nil)
    }

    private var task: (text: String, tint: Color?) {
        guard let run else { return ("–", nil) }
        switch run.outcome {
        case .loading:
            let percent = run.progress.map { " \(Int($0.fraction * 100))%" } ?? ""
            return ("loading" + percent, .blue)
        case .succeeded(let size):
            return ("\(size) · \(demoTime(run.duration ?? .zero))", .green)
        case .cancelled:
            return ("cancelled", .orange)
        case .failed(let error):
            return (error.demoCaseName, .red)
        }
    }

    private var slots: (text: String, tint: Color?) {
        guard let inFlight = figures.inFlightCount else { return ("–", nil) }
        let text = "\(inFlight) of \(figures.slotCount) held"
        guard figures.openCancelledCount > 0 else { return (text, nil) }
        return (text + " · stuck", .orange)
    }

    private func row(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        GridRow {
            DemoMonoLabel(label)
            DemoMonoLabel(value, tint: tint ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// The calls of the run on a line of time: a tick per chunk, sized by its
/// bytes, the pipeline's cancel, and the completion – or, after a cancel,
/// the wait for one.
private struct CallTimeline: View {
    let run: CustomDataLoaderDemoModel.Run

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !run.isOpen)) { _ in
            let end = run.completion?.time ?? run.elapsed
            // At least four seconds, so a short load doesn't fill the line.
            let span = max(end, .seconds(4))
            VStack(spacing: 2) {
                Canvas { context, size in
                    draw(in: &context, size: size, span: span, end: end)
                }
                .frame(height: 26)
                HStack {
                    DemoMonoLabel("0 s")
                    Spacer()
                    DemoMonoLabel(demoDelay(span))
                }
                .font(.caption2)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(run.chunks.count) chunks")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, span: Duration, end: Duration) {
        let baseline = size.height - 4
        func x(_ time: Duration) -> CGFloat {
            min(size.width - 3, 3 + (size.width - 6) * CGFloat(time.demoTimeInterval / span.demoTimeInterval))
        }
        var line = Path()
        line.move(to: CGPoint(x: 0, y: baseline))
        line.addLine(to: CGPoint(x: size.width, y: baseline))
        context.stroke(line, with: .color(Color(.separator)), lineWidth: 1)

        let chunks = run.chunks
        let largest = CGFloat(chunks.map(\.byteCount).max() ?? 1)
        for chunk in chunks {
            let height = 6 + (baseline - 8) * CGFloat(chunk.byteCount) / largest
            let rect = CGRect(x: x(chunk.time) - 1, y: baseline - height, width: 2, height: height)
            context.fill(Path(rect), with: .color(.blue))
        }
        if let cancel = run.cancel {
            let cancelX = x(cancel.time)
            context.fill(Path(CGRect(x: cancelX - 1, y: 0, width: 2, height: baseline)), with: .color(.orange))
            if run.completion == nil {
                var wait = Path()
                wait.move(to: CGPoint(x: cancelX, y: baseline))
                wait.addLine(to: CGPoint(x: x(end), y: baseline))
                context.stroke(wait, with: .color(.orange), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
            }
        }
        if let completion = run.completion {
            // Green after a cancel too: that completion frees the slot.
            let color: Color = completion.error == nil || run.cancel != nil ? .green : .red
            let dot = CGRect(x: x(completion.time) - 5, y: baseline - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: dot), with: .color(color))
        }
    }
}

// MARK: - List

/// The calls of the run, what the pipeline made of them, and the loader's
/// code.
private struct CustomDataLoaderList: View {
    @ObservedObject var model: CustomDataLoaderDemoModel
    /// Whether the Lab is on display, which its link follows.
    private let showsLab = DemoLaunchOptions.current.showsLab

    var body: some View {
        List {
            if let run = model.run {
                if let note = note(for: run) {
                    Section {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    if run.calls.isEmpty {
                        Text("Waiting for the pipeline to call the loader")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(CallGroup.fold(run.calls)) { group in
                        CallRow(group: group, run: run)
                    }
                    if run.isAwaitingCompletion {
                        MissingCompletionRow(run: run)
                    }
                } header: {
                    Text("Calls · Run \(run.number)")
                } footer: {
                    Text(callsFooter(for: run))
                }
                Section {
                    PipelineRows(run: run, figures: model.figures)
                    if showsLab {
                        DemoLink(.cancellationTorture)
                    }
                } header: {
                    Text("Pipeline")
                } footer: {
                    Text(pipelineFooter)
                }
            }
            Section {
                DemoCodeBlock(model.choice.code(failure: model.failure))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } header: {
                Text("Code")
            } footer: {
                Text(model.choice.codeFooter)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
    }

    private func callsFooter(for run: CustomDataLoaderDemoModel.Run) -> LocalizedStringKey {
        if run.choice == .throttled {
            return "ThrottledDataLoader calls nothing after a cancel, as the documentation of `DataLoading` asks. The pipeline frees a load's data loading slot only when `completion` is called, so today a load cancelled partway keeps its slot, and its pipeline, for as long as the app runs."
        }
        return "This loader calls `completion` after a cancel too, with `URLError(.cancelled)`, as `DataLoader` does. That frees the load's data loading slot, and reaches nothing of the app's: the pipeline let go of the task when it cancelled the load."
    }

    private var pipelineFooter: LocalizedStringKey {
        guard showsLab else {
            return "From the task's events and the demo's pipeline probe. A load is in flight, and holds its data loading slot, until the loader calls `completion`."
        }
        return "From the task's events and the demo's pipeline probe. A load is in flight, and holds its data loading slot, until the loader calls `completion`. Cancellation Torture's slot check cancels every download of a pipeline midway, with a loader that completes and one that doesn't, then asks for one more image."
    }

    /// What changes the calls of the run: the demo's switches in the Lab.
    private func note(for run: CustomDataLoaderDemoModel.Run) -> LocalizedStringKey? {
        if let conditions = run.conditions {
            let slots = run.choice == .throttled
                ? " It also completes a cancelled load itself, so ThrottledDataLoader's slot is freed here. Switch them off to see it kept."
                : ""
            return "Network conditions are on (\(conditions)): the loader is behind the Lab's rig, whose delays and failures come first.\(slots)"
        }
        if run.isOffline, run.choice == .throttled {
            return "Offline, the fixture loader answers in place of ThrottledDataLoader, at the same pace, with the photo's stand-in. It completes after a cancel, so no slot is kept here. Go online in Fixture Mode to see ThrottledDataLoader keep it."
        }
        return nil
    }
}

/// A call between the pipeline and the loader, or the chunks between the
/// first and the last, which would otherwise bury the calls around them.
private struct CallGroup: Identifiable {
    var calls: [CustomDataLoaderDemoModel.Call]

    var id: Int { calls[0].id }

    /// The calls in groups of one, but for the chunks in the middle of a run
    /// of them: the first chunk carries the response, and the last one is
    /// where the data has got to.
    static func fold(_ calls: [CustomDataLoaderDemoModel.Call]) -> [CallGroup] {
        var groups: [CallGroup] = []
        var index = calls.startIndex
        while index < calls.endIndex {
            var end = index
            while end < calls.endIndex, calls[end].chunk != nil {
                end += 1
            }
            guard end - index > 2 else {
                // A call that isn't a chunk, or too few chunks to fold.
                let next = max(end, index + 1)
                groups += calls[index..<next].map { CallGroup(calls: [$0]) }
                index = next
                continue
            }
            var middle = calls[index..<end]
            if middle.first?.chunk?.number == 1 {
                groups.append(CallGroup(calls: [middle.removeFirst()]))
            }
            let last = middle.removeLast()
            groups.append(CallGroup(calls: Array(middle)))
            groups.append(CallGroup(calls: [last]))
            index = end
        }
        return groups
    }
}

/// A call between the pipeline and the loader, or a run of chunks.
private struct CallRow: View {
    let group: CallGroup
    let run: CustomDataLoaderDemoModel.Run

    private var call: CustomDataLoaderDemoModel.Call { group.calls[0] }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            DemoMonoLabel(demoPad(demoTime(call.time), to: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .foregroundStyle(tint ?? .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                DemoMonoLabel(group.calls.count > 1 ? chunksDetail : detail)
                    .lineLimit(2)
            }
        }
    }

    private var title: String {
        switch call.kind {
        case .loadData: "loadData(with:)"
        case .didReceiveData: group.calls.count > 1 ? "didReceiveData ×\(group.calls.count)" : "didReceiveData"
        case .cancel: "cancel()"
        case .completion(let error): "completion(\(demoErrorName(error)))"
        }
    }

    /// "#2–#21 · 8,192 B each, 150 ms apart · 168 KB of 173 KB".
    private var chunksDetail: String {
        let chunks = group.calls.compactMap(\.chunk)
        guard let first = chunks.first, let last = chunks.last, let end = group.calls.last else { return "" }
        let apart = (end.time - call.time) / (chunks.count - 1)
        let sizes = chunks.map(\.byteCount)
        let smallest = sizes.min() ?? 0, largest = sizes.max() ?? 0
        let size = smallest == largest ? "\(largest.formatted()) B each" : "\(smallest.formatted())–\(largest.formatted()) B"
        var text = "#\(first.number)–#\(last.number) · \(size), \(demoDelay(apart)) apart · \(demoByteCount(last.total))"
        if last.expected > 0 {
            text += " of \(demoByteCount(last.expected))"
        }
        return text
    }

    private var tint: Color? {
        switch call.kind {
        case .cancel: .orange
        case .completion(.none): .green
        case .completion: run.cancel != nil ? .green : .red
        default: nil
        }
    }

    private var detail: String {
        switch call.kind {
        case let .loadData(request, loader):
            let path = request.url.map { "\($0.host() ?? "")/…/\($0.lastPathComponent)" } ?? "–"
            return "\(request.httpMethod ?? "GET") \(path) · \(loader.title)"
        case let .didReceiveData(number, byteCount, total, response):
            let length = response.expectedContentLength > 0 ? demoByteCount(response.expectedContentLength) : "no length"
            guard number > 1 else {
                // The first chunk comes with the response.
                let status = (response as? HTTPURLResponse).map { "\($0.statusCode)" } ?? "URLResponse"
                return "#1 · \(byteCount.formatted()) B · \(status), \(length)"
            }
            return "#\(number) · \(byteCount.formatted()) B · \(demoByteCount(total)) of \(length)"
        case .cancel:
            return "the pipeline cancelled the load"
        case .completion(let error):
            if let cancel = run.cancel {
                return "\(demoDelay(call.time - cancel.time)) after the cancel: the slot is free"
            }
            guard let error else { return "the data is complete" }
            return demoLoaderErrorMessage(error)
        }
    }
}

/// The completion a cancelled load of ThrottledDataLoader never makes.
private struct MissingCompletionRow: View {
    let run: CustomDataLoaderDemoModel.Run

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { _ in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                DemoMonoLabel(demoPad("", to: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text("no completion")
                        .font(.system(.footnote, design: .monospaced).weight(.medium))
                        .foregroundStyle(.orange)
                    if let cancel = run.cancel {
                        DemoMonoLabel("\(demoDelay(run.elapsed - cancel.time)) since the cancel: the slot stays held", tint: .orange)
                    }
                }
            }
        }
    }
}

/// What the pipeline made of the calls, and what the probe counted.
private struct PipelineRows: View {
    let run: CustomDataLoaderDemoModel.Run
    let figures: CustomDataLoaderDemoModel.Figures

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 6) {
            row("progress", progress)
            row("result", result.text, tint: result.tint)
            row("downloads", downloads)
            row("in flight", inFlight.text, tint: inFlight.tint)
            row("earlier runs", earlier.text, tint: earlier.tint)
        }
        .padding(.vertical, 2)
    }

    private var progress: String {
        guard let progress = run.progress else { return "no events yet" }
        return "\(demoCount(run.progressEventCount, "event")) · \(demoByteCount(progress.completed)) of \(demoByteCount(progress.total))"
    }

    private var result: (text: String, tint: Color?) {
        switch run.outcome {
        case .loading:
            ("loading", .blue)
        case .succeeded(let size):
            ("\(size) image in \(demoTime(run.duration ?? .zero, sign: false))", .green)
        case .cancelled:
            ("cancelled", .orange)
        case .failed(let error):
            ("\(error.demoCaseName): \(error.demoMessage)", .red)
        }
    }

    private var downloads: String {
        var parts = ["\(figures.downloadCount) started", "\(figures.completedCount) completed"]
        if figures.failedCount > 0 {
            parts.append("\(figures.failedCount) failed")
        }
        if figures.cancelledCount > 0 {
            parts.append("\(figures.cancelledCount) cancelled")
        }
        return parts.joined(separator: " · ")
    }

    private var inFlight: (text: String, tint: Color?) {
        guard let count = figures.inFlightCount else { return ("–", nil) }
        let text = "\(count) of \(figures.slotCount) slots"
        guard figures.openCancelledCount > 0 else { return (text, nil) }
        return (text + " · \(figures.openCancelledCount) cancelled and never completed", .orange)
    }

    private var earlier: (text: String, tint: Color?) {
        let count = figures.earlierHeldCount
        guard count > 0 else { return ("no pipeline kept", nil) }
        let text = count == 1 ? "1 pipeline kept alive, holding a slot" : "\(count) pipelines kept alive, a slot each"
        return (text, .orange)
    }

    private func row(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        GridRow {
            // At its own width, which leaves the rest to the value: a grid
            // splits the width between columns that can wrap.
            DemoMonoLabel(label)
                .fixedSize()
            DemoMonoLabel(value, tint: tint ?? .primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Loaders

/// The loaders on the picker.
private enum LoaderChoice: String, CaseIterable, Identifiable {
    case throttled
    case bundle
    case failing

    var id: Self { self }

    var title: String {
        switch self {
        case .throttled: "Throttled"
        case .bundle: "Bundle"
        case .failing: "Failing"
        }
    }

    var typeName: String {
        switch self {
        case .throttled: "ThrottledDataLoader"
        case .bundle: "BundleDataLoader"
        case .failing: "FailingDataLoader"
        }
    }

    /// Where the pipeline gets it from.
    var installation: String {
        switch self {
        case .throttled, .failing: "configuration.dataLoader"
        case .bundle: "delegate.dataLoader(for:)"
        }
    }

    var codeFooter: LocalizedStringKey {
        switch self {
        case .throttled:
            "`ThrottledDataLoader`, in the demo's Helpers. It downloads with a session of its own, which has no `URLCache`, so every run goes to the server."
        case .bundle:
            "`BundleDataLoader`, next to this screen. Every other request of the pipeline goes to its configured `DataLoader`."
        case .failing:
            "`FailingDataLoader`, next to this screen. The bytes of the cut-off body are zeros: the pipeline doesn't decode an unfinished body unless progressive decoding is on."
        }
    }

    /// The loader, the way the pipeline gets it, and what it does in
    /// `loadData`; the failing one with the failure picked.
    func code(failure: FailingDataLoader.Failure) -> String {
        switch self {
        case .throttled:
            """
            var configuration = ImagePipeline.Configuration()
            configuration.dataLoader = ThrottledDataLoader(chunkSize: 8_192, interval: .milliseconds(150))

            final class ThrottledDataLoader: DataLoading {
                func loadData(
                    with request: URLRequest,
                    didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
                    completion: @escaping @Sendable (Error?) -> Void
                ) -> any Cancellable {
                    let task = Task {
                        do {
                            let (data, response) = try await session.data(for: request)
                            var offset = 0
                            while offset < data.count {
                                try await Task.sleep(for: interval)
                                let end = min(offset + chunkSize, data.count)
                                didReceiveData(data[offset..<end], response)
                                offset = end
                            }
                            completion(nil)
                        } catch {
                            // The pipeline doesn't expect any callbacks after cancellation.
                            if !Task.isCancelled {
                                completion(error)
                            }
                        }
                    }
                    return AnyCancellable { task.cancel() }
                }
            }
            """
        case .bundle:
            """
            final class BundleFirstDelegate: ImagePipeline.Delegate {
                let bundleLoader = BundleDataLoader(files: [photoURL: "fixture-still.webp"])

                func dataLoader(for request: ImageRequest, pipeline: ImagePipeline) -> any DataLoading {
                    bundleLoader.canLoad(request) ? bundleLoader : pipeline.configuration.dataLoader
                }
            }

            final class BundleDataLoader: DataLoading {
                func loadData(
                    with request: URLRequest,
                    didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
                    completion: @escaping @Sendable (Error?) -> Void
                ) -> any Cancellable {
                    let task = Task {
                        do {
                            guard let url = request.url, let name = files[url],
                                  let file = Bundle.main.url(forResource: name, withExtension: nil) else {
                                throw URLError(.fileDoesNotExist)
                            }
                            let data = try Data(contentsOf: file)
                            let response = URLResponse(url: url, mimeType: nil, expectedContentLength: data.count, textEncodingName: nil)
                            var offset = 0
                            while offset < data.count {
                                try await Task.sleep(for: interval)
                                let end = min(offset + chunkSize, data.count)
                                didReceiveData(data[offset..<end], response)
                                offset = end
                            }
                            completion(nil)
                        } catch {
                            // After a cancel too: the call frees the load's slot.
                            completion(Task.isCancelled ? URLError(.cancelled) : error)
                        }
                    }
                    return AnyCancellable { task.cancel() }
                }
            }
            """
        case .failing:
            """
            var configuration = ImagePipeline.Configuration()
            configuration.dataLoader = FailingDataLoader(failure: .\(failure.rawValue))

            final class FailingDataLoader: DataLoading {
                func loadData(
                    with request: URLRequest,
                    didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
                    completion: @escaping @Sendable (Error?) -> Void
                ) -> any Cancellable {
                    let task = Task {
                        do {
                            try await Task.sleep(for: .milliseconds(400))
                            switch failure {
                            case .serverError:
                                throw DataLoader.Error.statusCodeUnacceptable(500)
                            case .connectionLost:
                                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "98304"])!
                                for _ in 0..<4 {
                                    try await Task.sleep(for: .milliseconds(200))
                                    didReceiveData(Data(count: 8_192), response)
                                }
                                throw URLError(.networkConnectionLost, userInfo: [
                                    NSLocalizedDescriptionKey: "The network connection was lost.",
                                    NSURLErrorFailingURLErrorKey: url
                                ])
                            }
                        } catch {
                            completion(Task.isCancelled ? URLError(.cancelled) : error)
                        }
                    }
                    return AnyCancellable { task.cancel() }
                }
            }
            """
        }
    }
}

extension FailingDataLoader.Failure {
    fileprivate var title: String {
        switch self {
        case .serverError: "500 Server Error"
        case .connectionLost: "Connection Lost"
        }
    }
}

// Neither goes to the network, so the demo's probe leaves their requests to
// them while the demo is offline.
extension BundleDataLoader: DemoLocalDataLoading {}
extension FailingDataLoader: DemoLocalDataLoading {}

/// Sends the requests the bundle has a file for to the bundle loader, and
/// every other one to the loader the pipeline was configured with.
private final class BundleFirstDelegate: ImagePipeline.Delegate {
    let bundleLoader: BundleDataLoader

    init(bundleLoader: BundleDataLoader) {
        self.bundleLoader = bundleLoader
    }

    func dataLoader(for request: ImageRequest, pipeline: ImagePipeline) -> any DataLoading {
        bundleLoader.canLoad(request) ? bundleLoader : pipeline.configuration.dataLoader
    }
}

// MARK: - Model

/// Runs the picked loader and keeps what it did.
///
/// Every run is one image task on a pipeline of its own, so that the slot a
/// cancelled ThrottledDataLoader load keeps doesn't hold up the next run.
/// The earlier pipelines are held weakly: one that is still alive a moment
/// after its run is kept by a load that never completed. The calls come from
/// the probe's load events, and what the pipeline made of them from the
/// task's events.
@MainActor
private final class CustomDataLoaderDemoModel: ObservableObject {
    /// One load of the image.
    struct Run {
        enum Outcome {
            case loading
            /// With the size of the image, such as "1024×772".
            case succeeded(String)
            case cancelled
            case failed(ImagePipeline.Error)
        }

        let number: Int
        let choice: LoaderChoice
        let startedAt: ContinuousClock.Instant
        /// The demo's switches when the run started, which is when the probe
        /// read them for its load.
        let isOffline: Bool
        /// The title of the network conditions, if they were on.
        let conditions: String?
        /// The loader that answered, after the probe's routing.
        var loader: AnsweringLoader?
        var calls: [Call] = []
        var progress: ImageTask.Progress?
        var progressEventCount = 0
        var outcome: Outcome = .loading
        var duration: Duration?
        var image: UIImage?

        var isLoading: Bool {
            if case .loading = outcome { true } else { false }
        }

        /// The time since the run started.
        var elapsed: Duration {
            startedAt.duration(to: .now)
        }

        var cancel: Call? {
            calls.first { if case .cancel = $0.kind { true } else { false } }
        }

        var completion: (time: Duration, error: (any Error)?)? {
            for call in calls {
                if case .completion(let error) = call.kind {
                    return (call.time, error)
                }
            }
            return nil
        }

        var chunks: [(time: Duration, byteCount: Int, total: Int)] {
            calls.compactMap { call in
                guard case let .didReceiveData(_, byteCount, total, _) = call.kind else { return nil }
                return (call.time, byteCount, total)
            }
        }

        var response: URLResponse? {
            for call in calls {
                if case let .didReceiveData(_, _, _, response) = call.kind {
                    return response
                }
            }
            return nil
        }

        /// Cancelled, and the loader hasn't called `completion` since.
        var isAwaitingCompletion: Bool {
            cancel != nil && completion == nil
        }

        /// Whether anything on the timeline can still happen.
        var isOpen: Bool {
            isLoading || completion == nil
        }
    }

    /// A call between the pipeline and the loader, timed from the start of
    /// the run.
    struct Call: Identifiable {
        enum Kind {
            case loadData(URLRequest, AnsweringLoader)
            case didReceiveData(number: Int, byteCount: Int, total: Int, response: URLResponse)
            case cancel
            case completion((any Error)?)
        }

        let id: Int
        let time: Duration
        let kind: Kind

        /// For `didReceiveData`: its number, size, the bytes so far, and the
        /// length the response expects.
        var chunk: (number: Int, byteCount: Int, total: Int, expected: Int64)? {
            guard case let .didReceiveData(number, byteCount, total, response) = kind else { return nil }
            return (number, byteCount, total, response.expectedContentLength)
        }
    }

    /// What the probe counted for the run's pipeline, and for the earlier
    /// runs' pipelines that are still alive.
    struct Figures: Equatable {
        var inFlightCount: Int?
        var slotCount = 0
        /// Loads cancelled in flight whose loader hasn't completed them.
        var openCancelledCount = 0
        var downloadCount = 0
        var completedCount = 0
        var failedCount = 0
        var cancelledCount = 0
        /// The earlier pipelines still alive that hold a slot.
        var earlierHeldCount = 0
    }

    @Published var choice: LoaderChoice = .throttled {
        didSet {
            guard choice != oldValue else { return }
            startRun()
        }
    }

    @Published var failure: FailingDataLoader.Failure = .serverError {
        didSet {
            guard failure != oldValue, choice == .failing else { return }
            startRun()
        }
    }

    @Published private(set) var run: Run?
    @Published private(set) var figures = Figures()

    /// The image every run requests: the WebP, whose stand-in the app
    /// bundle has.
    private let url = DemoImages.Network.webp

    // The loaders are made once: each one is stateless between loads.
    private let throttledLoader = ThrottledDataLoader(chunkSize: 8_192, interval: .milliseconds(150))
    private let bundleLoader: BundleDataLoader
    private let failingLoaders = FailingDataLoader.Failure.allCases.map(FailingDataLoader.init(failure:))
    /// Loads what the bundle doesn't have. Nothing here asks it to.
    private let networkLoader: DataLoader
    private let imageCache = ImageCache()
    private let dataCache = try? DataCache(name: "com.github.kean.NukeDemo.CustomDataLoader")
    private let relay = Relay()

    private var pipeline: ImagePipeline?
    private var earlierPipelines: [WeakPipeline] = []
    private var task: ImageTask?
    private var lastRunNumber = 0
    private var lastCallID = 0

    init() {
        bundleLoader = BundleDataLoader(files: [DemoImages.Network.webp: "fixture-still.webp"])
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        networkLoader = DataLoader(configuration: configuration)
        relay.model = self
    }

    // MARK: Actions

    func runIfNeeded() {
        guard run == nil else { return }
        startRun()
    }

    /// Loads the image on a new pipeline with the picked loader, and cancels
    /// the load in flight, if any.
    func startRun() {
        cancel()
        if let pipeline {
            earlierPipelines.append(WeakPipeline(pipeline: pipeline))
        }
        lastRunNumber += 1
        let run = Run(
            number: lastRunNumber,
            choice: choice,
            startedAt: .now,
            isOffline: DemoFixtureMode.isOffline,
            conditions: DemoNetworkConditions.shared.isOn ? DemoNetworkConditions.shared.title : nil
        )
        let pipeline = makePipeline(for: run)
        self.pipeline = pipeline
        self.run = run

        // Reads neither cache, and writes both.
        let task = pipeline.imageTask(with: ImageRequest(url: url, options: [.reloadIgnoringCachedData]))
        self.task = task
        let number = run.number
        Task { [weak self] in
            for await event in task.events {
                self?.handle(event, runNumber: number)
            }
        }
        sampleFigures()
    }

    /// Cancels the task, the way a view that goes away does, and keeps
    /// listening: the loader may have more to say.
    func cancel() {
        guard let task, run?.isLoading == true else { return }
        task.cancel()
    }

    private func makePipeline(for run: Run) -> ImagePipeline {
        var configuration: ImagePipeline.Configuration
        var delegate: (any ImagePipeline.Delegate)?
        switch run.choice {
        case .throttled:
            configuration = ImagePipeline.Configuration(dataLoader: throttledLoader)
        case .bundle:
            configuration = ImagePipeline.Configuration(dataLoader: networkLoader)
            delegate = BundleFirstDelegate(bundleLoader: bundleLoader)
        case .failing:
            configuration = ImagePipeline.Configuration(dataLoader: failingLoaders.first { $0.failure == failure } ?? failingLoaders[0])
        }
        // A new configuration has queues of its own; the caches are shared.
        configuration.imageCache = imageCache
        configuration.dataCache = dataCache
        let relay = relay
        let number = run.number
        return DemoPipelineProbe.makePipeline("Custom Data Loader · \(run.choice.title) · \(number)", configuration: configuration, delegate: delegate, onLoad: { event in
            let now = ContinuousClock.now
            let kind = event.kind
            Task { @MainActor in
                relay.model?.record(kind, at: now, runNumber: number)
            }
        })
    }

    // MARK: Reports

    private func record(_ kind: DemoPipelineProbe.LoadEvent.Kind, at instant: ContinuousClock.Instant, runNumber: Int) {
        guard var run, run.number == runNumber else { return }
        let time = run.startedAt.duration(to: instant)
        lastCallID += 1
        let call: Call
        switch kind {
        case let .started(request, loader):
            let answering = AnsweringLoader(loader)
            run.loader = answering
            call = Call(id: lastCallID, time: time, kind: .loadData(request, answering))
        case let .received(byteCount, response):
            let chunks = run.chunks
            let number = chunks.count + 1
            call = Call(id: lastCallID, time: time, kind: .didReceiveData(number: number, byteCount: byteCount, total: (chunks.last?.total ?? 0) + byteCount, response: response))
        case .cancelled:
            call = Call(id: lastCallID, time: time, kind: .cancel)
        case .completed(let error):
            call = Call(id: lastCallID, time: time, kind: .completion(error))
        }
        // The reports hop to the main actor one by one, from more than one
        // thread: keep them in the order they happened.
        let index = run.calls.lastIndex { $0.time <= time }.map { $0 + 1 } ?? 0
        run.calls.insert(call, at: index)
        self.run = run
    }

    private func handle(_ event: ImageTask.Event, runNumber: Int) {
        guard var run, run.number == runNumber else { return }
        switch event {
        case .progress(let progress):
            run.progress = progress
            run.progressEventCount += 1
        case .preview:
            break
        case .finished(let result):
            run.duration = run.elapsed
            switch result {
            case .success(let response):
                run.image = response.image
                let size = response.image.cgImage.map { "\($0.width)×\($0.height)" } ?? "an"
                run.outcome = .succeeded(size)
            case .failure(.cancelled):
                run.outcome = .cancelled
            case .failure(let error):
                run.outcome = .failed(error)
            }
        }
        self.run = run
    }

    // MARK: Figures

    func sampleFigures() {
        var figures = Figures()
        if let pipeline, let current = DemoPipelineProbe.diagnostics(for: pipeline) {
            figures.inFlightCount = current.dataLoadingQueue.inFlightCount
            figures.slotCount = current.dataLoadingQueue.limit
            figures.openCancelledCount = current.cancelledInFlightDownloadCount
            figures.downloadCount = current.downloadCount
            figures.completedCount = current.completedDownloadCount
            figures.failedCount = current.failedTaskCount
            figures.cancelledCount = current.cancelledDownloadCount
        }
        earlierPipelines.removeAll { $0.pipeline == nil }
        figures.earlierHeldCount = earlierPipelines.count(where: { box in
            guard let pipeline = box.pipeline else { return false }
            return (DemoPipelineProbe.diagnostics(for: pipeline)?.cancelledInFlightDownloadCount ?? 0) > 0
        })
        if figures != self.figures {
            self.figures = figures
        }
    }

    typealias Relay = DemoRelay<CustomDataLoaderDemoModel>

    private struct WeakPipeline {
        weak var pipeline: ImagePipeline?
    }
}

/// The loader the pipeline called, as the probe routed the request.
private struct AnsweringLoader {
    /// Its type, such as `ThrottledDataLoader`.
    let name: String
    /// Whether it is behind the Lab's network conditions.
    let isConditioned: Bool

    init(_ loader: any DataLoading) {
        let conditioned = loader as? DemoConditionedDataLoader
        let base = conditioned?.base ?? loader
        name = String(describing: type(of: base))
        isConditioned = conditioned != nil
    }

    var title: String {
        isConditioned ? "\(name), behind the network conditions" : name
    }

    var shortTitle: String {
        isConditioned ? "\(name) +rig" : name
    }
}

// MARK: - Helpers

/// The name of an error a loader completed with, the way the code spells it.
private func demoErrorName(_ error: (any Error)?) -> String {
    switch error {
    case nil:
        return "nil"
    case let error as URLError:
        let name = switch error.code {
        case .cancelled: ".cancelled"
        case .networkConnectionLost: ".networkConnectionLost"
        case .timedOut: ".timedOut"
        case .fileDoesNotExist: ".fileDoesNotExist"
        case .notConnectedToInternet: ".notConnectedToInternet"
        default: "\(error.code.rawValue)"
        }
        return "URLError(\(name))"
    case let error as DataLoader.Error:
        if case .statusCodeUnacceptable(let code) = error {
            return ".statusCodeUnacceptable(\(code))"
        }
        return "\(error)"
    case let error?:
        return String(describing: type(of: error))
    }
}

/// The error a loader completed with, in a few characters.
private func demoShortErrorName(_ error: (any Error)?) -> String {
    switch error {
    case nil: "nil"
    case let error as URLError where error.code == .cancelled: "cancelled"
    case let error?: demoLoaderErrorSummary(error) ?? String(describing: type(of: error))
    }
}

/// "+1.24 s".
private func demoTime(_ duration: Duration, sign: Bool = true) -> String {
    (sign ? "+" : "") + String(format: "%.2f s", duration.demoTimeInterval)
}

/// "4 ms", "0.3 ms", "2.1 s".
private func demoDelay(_ duration: Duration) -> String {
    let seconds = duration.demoTimeInterval
    switch seconds {
    case ..<0.001: return String(format: "%.1f ms", seconds * 1000)
    case ..<1: return String(format: "%.0f ms", seconds * 1000)
    default: return String(format: "%.1f s", seconds)
    }
}
