// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import os
import SwiftUI

/// Demonstrates resumable downloads: a download cancelled partway picks up
/// where it stopped the next time the image is requested.
///
/// ```swift
/// var configuration = ImagePipeline.Configuration()
/// configuration.isResumableDataEnabled = true // The default
/// ```
///
/// The pipeline keeps the bytes of a download that ends early, and the next
/// request for the image asks the server for the rest with a `Range` header.
/// Every attempt is listed with the request as it went out, read from the
/// `willLoadData` event of the demo's pipeline probe, which the pipeline
/// calls after it added the headers, and the response as the data loader
/// received it.
///
/// The loader hands the image to the pipeline a few kilobytes at a time, so
/// that there is time to cancel, and ends every load with a `completion`,
/// a cancelled one included. Offline, the fixture loader that stands in for
/// it answers like a server that supports range requests.
struct ResumableDownloadsDemo: View {
    @StateObject private var model = ResumableDownloadsDemoModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        // The download above the attempts, except on a phone on its side,
        // which has the width for both and not the height.
        let isSideBySide = verticalSizeClass == .compact
        let layout = isSideBySide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        let stage = ResumableDownloadsStage(model: model, isWide: horizontalSizeClass == .regular && !isSideBySide)
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
            ResumableDownloadsList(model: model)
        }
        .background(Color(.systemGroupedBackground))
        .onDisappear { model.cancel() }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Resumable Downloads",
        "When a download ends early, the pipeline keeps the bytes it received, and the next request for the image asks the server for the rest. The bar shows which attempt each byte of the image came from, and every attempt below shows the request that went out and the response that came back.",
        code: """
        var configuration = ImagePipeline.Configuration()
        configuration.isResumableDataEnabled = true // The default

        task.cancel()

        // The next request for the image goes out with
        // Range: bytes=131072-
        // If-Range: "62701a1c57a0ed2a783004e592ff2d30"
        let image = try await pipeline.image(for: url)
        """,
        points: [
            .init("Try it", "Start, then Cancel partway. Resume requests the image again: the request carries a `Range` header for the bytes the pipeline doesn't have, the server answers `206 Partial Content` with only those, and the figures count what wasn't downloaded again. Start Over forgets the download and begins a new one."),
            .init("What it takes", "The pipeline keeps a download that ended early only if its response has a `Content-Length` the bytes fell short of, a status of 200 or 206, `Accept-Ranges: bytes`, and a validator: an `ETag` or a `Last-Modified`. The next request asks for the rest with `Range` and sends the validator in `If-Range`. The pipeline uses the kept bytes only if the server answers 206; a server whose image changed since answers 200 with all of it, and the download starts over."),
            .init("Validators", "Turn them off, and the loader takes the `ETag` and `Last-Modified` out of every response before the pipeline sees it, the way a server without them answers. The pipeline keeps nothing, and the next attempt downloads the whole image again."),
            .init("Kept per pipeline", "The pipelines of an app share one store of partial downloads, in memory, but each pipeline finds only its own: the store is keyed by the pipeline and the request's `imageID`. An app that makes a pipeline for every screen never resumes. Turn on New Pipeline Each Attempt to see it."),
            .init("Start Over", "There's no public call that empties the store, so Start Over gives the request a new `imageID`, which nothing is kept under, and empties the caches. The same key works the other way: a URL with a token that changes on every request resumes if the request's `imageID` leaves the token out."),
            .init("How much is kept", "Up to 100 downloads and 1% of the device's memory – not the 32 MB the documentation says – and a single download bigger than a tenth of that isn't kept at all. The store is emptied when memory runs low, and cut to a tenth when the app goes to the background."),
            .init("A second cancel", "The pipeline decides whether to keep a download by comparing the bytes it has with the response's `Content-Length`. For a resumed download, that is the length of the rest, not of the image. Cancel a resumed download after it has more bytes than the rest is long, and nothing is kept: the next attempt starts from the first byte. Cancel it earlier, and it resumes again."),
            .init("What an app sees", "The delegate's `willLoadData` receives the request with the `Range` and `If-Range` headers already in it, which is where this screen reads them. The task's progress counts the kept bytes from the start of a resumed attempt, and the task's `ImageTask.Metrics` records them in `bytes.resumed`; `bytes.downloaded` counts them too."),
            .init("The loader", "This screen's loader downloads each response at full speed and hands it to the pipeline 8 KB at a time, 100 ms apart, so a cancel leaves the pipeline holding part of the image, the way a slow network would. The requests and the responses are real: the resumed request asks the server for the rest, and the server sends only that. The loader ends every load with a call to `completion`, a cancelled one included, which frees the load's data loading slot."),
            .init("The image", "The landscape photo, a 310 KB baseline JPEG and the largest still image the demo loads. Its host, user-images.githubusercontent.com, answers range requests and sends an `ETag` and a `Last-Modified`. Offline, the fixture loader serves a 1440 × 960 fixture in its place and answers the same way, with an `ETag` made of the fixture's digest."),
            .init("Caches", "The pipeline has a memory cache and a `DataCache` of its own, emptied when the screen opens and by Start Over, so a new download doesn't come from them. Until its last byte arrives, a download is in neither cache: only the store of partial downloads holds it.")
        ]
    )
}

// MARK: - Stage

/// The image, the figures, the bar, and the controls.
private struct ResumableDownloadsStage: View {
    @ObservedObject var model: ResumableDownloadsDemoModel
    /// Gives the image more room, where there is more.
    let isWide: Bool

    var body: some View {
        let figures = model.figures
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                preview(figures)
                    .frame(width: isWide ? 240 : 132)
                FiguresView(figures: figures, attemptCount: model.attempts.count)
            }
            ByteBar(figures: figures)
            legend(figures)
            controls
        }
    }

    private func preview(_ figures: ResumableDownloadsDemoModel.Figures) -> some View {
        Color(.secondarySystemGroupedBackground)
            .aspectRatio(3 / 2, contentMode: .fit)
            .overlay {
                if let image = model.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else if let fraction = figures.fraction {
                    Text("\(Int(fraction * 100))%")
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Each attempt the image is made of, in the colors of the bar.
    private func legend(_ figures: ResumableDownloadsDemoModel.Figures) -> some View {
        var text = Text(" ")
        if !figures.segments.isEmpty {
            let parts = figures.segments.map { segment in
                Text("\(Text(Image(systemName: "circle.fill")).foregroundStyle(attemptColor(segment.attemptNumber))) \(segment.attemptNumber) · \(demoByteCount(segment.byteCount))")
            }
            text = parts.dropFirst().reduce(parts[0]) { Text("\($0)   \($1)") }
        }
        return text
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// Without the icons where the row doesn't fit with them: beside the
    /// attempts on a phone on its side.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            controlRow
            controlRow
                .labelStyle(.titleOnly)
        }
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            if model.attempts.isEmpty {
                Button("Start", systemImage: "arrow.down") { model.start() }
            } else {
                Button("Resume", systemImage: "play") { model.resume() }
                    .disabled(!model.canResume)
            }
            Button("Cancel", systemImage: "xmark") { model.cancel() }
                .disabled(!model.isLoading)
            Spacer(minLength: 8)
            Button("Start Over", systemImage: "arrow.counterclockwise") { model.startOver() }
                .disabled(model.attempts.isEmpty)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// What the download cost, over every attempt since it started.
private struct FiguresView: View {
    let figures: ResumableDownloadsDemoModel.Figures
    let attemptCount: Int

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            row("image", image)
            row("downloaded", attemptCount == 0 ? "–" : "\(demoByteCount(figures.downloadedByteCount)) in \(demoCount(attemptCount, "attempt"))")
            row("saved", attemptCount == 0 ? "–" : "\(demoByteCount(figures.resumedByteCount)) resumed", tint: figures.resumedByteCount > 0 ? .green : nil)
            row("wasted", attemptCount == 0 ? "–" : "\(demoByteCount(figures.wastedByteCount)) re-downloaded", tint: figures.wastedByteCount > 0 ? .orange : nil)
        }
    }

    private var image: String {
        guard let count = figures.imageByteCount else { return "–" }
        var text = demoByteCount(count)
        if let pixelSize = figures.pixelSize {
            text += " · \(pixelSize)"
        } else if let fraction = figures.fraction {
            text += " · \(Int(fraction * 100))%"
        }
        return text
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

/// The bytes of the image, colored by the attempt that downloaded them.
private struct ByteBar: View {
    let figures: ResumableDownloadsDemoModel.Figures

    var body: some View {
        GeometryReader { proxy in
            let total = CGFloat(max(1, figures.imageByteCount ?? 0))
            ZStack(alignment: .leading) {
                ForEach(figures.segments) { segment in
                    attemptColor(segment.attemptNumber)
                        .frame(width: max(0, proxy.size.width * CGFloat(segment.byteCount) / total))
                        // A hairline between two attempts.
                        .overlay(alignment: .leading) {
                            if segment.lowerBound > 0 {
                                Color(.systemBackground)
                                    .frame(width: 1)
                            }
                        }
                        .offset(x: proxy.size.width * CGFloat(segment.lowerBound) / total)
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
        }
        .frame(height: 10)
        .background(Color(.systemFill))
        .clipShape(Capsule())
        .animation(.linear(duration: 0.1), value: figures.segments)
    }
}

// MARK: - Attempts

/// Every attempt, the last one first, and the conditions.
private struct ResumableDownloadsList: View {
    @ObservedObject var model: ResumableDownloadsDemoModel

    var body: some View {
        List {
            if model.attempts.isEmpty {
                Section {
                    Text("Start the download, then cancel it partway. Resume requests the image again, and the pipeline asks the server only for the bytes it doesn't have.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(model.attempts.reversed()) { attempt in
                Section {
                    RequestRow(attempt: attempt)
                    ResponseRow(attempt: attempt)
                    BytesRow(attempt: attempt, next: model.attempt(after: attempt))
                } header: {
                    AttemptHeader(attempt: attempt, showsPipeline: model.hasSeveralPipelines)
                } footer: {
                    if let note = model.note(for: attempt) {
                        Text(note)
                    }
                }
            }
            Section {
                Toggle("Validators", isOn: $model.sendsValidators)
                Toggle("New Pipeline Each Attempt", isOn: $model.usesNewPipeline)
            } header: {
                Text("Conditions")
            } footer: {
                Text(conditionsFooter)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
    }

    private var conditionsFooter: LocalizedStringKey {
        let server = model.isOffline
            ? "Offline, the fixture loader answers in place of the server."
            : "The server is user-images.githubusercontent.com."
        return "Validators are the server's `ETag` and `Last-Modified`. Without them, the loader takes both out of every response, and the pipeline keeps nothing to resume. New Pipeline Each Attempt requests the image again on a pipeline that has kept nothing. Both apply from the next attempt. \(server)"
    }
}

private struct AttemptHeader: View {
    let attempt: ResumableDownloadsDemoModel.Attempt
    let showsPipeline: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("\(attempt.number)")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(attemptColor(attempt.number))
                .frame(width: 28, height: 28)
                .background(attemptColor(attempt.number).opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text("Attempt \(attempt.number)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                DemoMonoLabel(attempt.status, tint: attempt.statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            if showsPipeline {
                DemoMonoLabel("pipeline \(attempt.pipelineNumber)")
            }
        }
        .textCase(nil)
        .padding(.top, 4)
    }
}

/// The request as it went out: the pipeline's delegate sees it in
/// `willLoadData`, with the headers the pipeline added.
private struct RequestRow: View {
    let attempt: ResumableDownloadsDemoModel.Attempt

    var body: some View {
        HeaderBlock(title: "Request") {
            if let sent = attempt.sent {
                HeaderLine("GET", sent.path, tint: .primary, truncatesMiddle: true)
                HeaderLine("Host", sent.host)
                if let range = sent.range {
                    HeaderLine("Range", range, tint: .blue)
                    HeaderLine("If-Range", sent.ifRange ?? "none", tint: .blue, truncatesMiddle: true)
                } else {
                    HeaderLine("Range", "none")
                }
            } else {
                HeaderLine("", attempt.isActive ? "waiting to go out" : "never went out")
            }
        }
    }
}

/// The response as the loader received it, before the pipeline saw it.
private struct ResponseRow: View {
    let attempt: ResumableDownloadsDemoModel.Attempt

    var body: some View {
        HeaderBlock(title: "Response") {
            if let received = attempt.received {
                HeaderLine("Status", received.statusLine, tint: received.statusCode == 206 ? .green : .primary)
                if let contentRange = received.contentRange {
                    HeaderLine("Content-Range", contentRange, tint: .green)
                }
                HeaderLine("Content-Length", received.contentLength ?? "none")
                HeaderLine("ETag", received.entityTag ?? "none", tint: received.entityTag == nil ? .orange : nil, truncatesMiddle: true)
                HeaderLine("Last-Modified", received.lastModified ?? "none", tint: received.lastModified == nil ? .orange : nil)
                HeaderLine("Accept-Ranges", received.acceptRanges ?? "none", tint: received.acceptRanges == nil ? .orange : nil)
            } else {
                HeaderLine("", attempt.isActive ? "waiting for the server" : "none")
            }
        }
    }
}

/// The bytes of the attempt: what it downloaded, and what the pipeline kept.
private struct BytesRow: View {
    let attempt: ResumableDownloadsDemoModel.Attempt
    let next: ResumableDownloadsDemoModel.Attempt?

    var body: some View {
        HeaderBlock(title: "Bytes") {
            HeaderLine("Downloaded", downloaded)
            if attempt.resumedByteCount > 0 {
                HeaderLine("Resumed", "\(demoByteCount(attempt.resumedByteCount)) kept from before", tint: .green)
            }
            if let kept {
                HeaderLine("Kept", kept.text, tint: kept.tint)
            }
            if let record = attempt.record {
                HeaderLine("Metrics", "downloaded \(demoByteCount(record.downloaded)) · resumed \(demoByteCount(record.resumed))")
            }
        }
    }

    private var downloaded: String {
        var text = demoByteCount(attempt.downloadedByteCount)
        if let duration = attempt.duration {
            text += String(format: " in %.1f s", duration)
        }
        return text
    }

    /// For an attempt that ended early, what the next one started from, or
    /// until there is one, what the pipeline's rules keep.
    private var kept: (text: String, tint: Color?)? {
        guard attempt.state == .cancelled || attempt.isFailed else { return nil }
        guard let next, next.startsFromFirstByte != nil else {
            let keep = attempt.expectedKeep
            guard keep.byteCount > 0 else {
                return ("nothing: \(keep.reason ?? "–")", .orange)
            }
            return ("\(demoByteCount(keep.byteCount)), for the next attempt", nil)
        }
        let offset = next.startOffset
        guard offset > 0 else {
            return ("nothing", .orange)
        }
        return ("\(demoByteCount(offset)), resumed by attempt \(next.number)", .green)
    }
}

/// A titled block of name–value lines, in the style of HTTP headers.
private struct HeaderBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                content
            }
        }
        .padding(.vertical, 2)
    }
}

private struct HeaderLine: View {
    let name: String
    let value: String
    var tint: Color?
    var truncatesMiddle = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(_ name: String, _ value: String, tint: Color? = nil, truncatesMiddle: Bool = false) {
        self.name = name
        self.value = value
        self.tint = tint
        self.truncatesMiddle = truncatesMiddle
    }

    var body: some View {
        GridRow {
            // Where there's the width, as wide as the longest name, so the
            // values of every block line up.
            DemoMonoLabel(horizontalSizeClass == .regular ? "Content-Length" : name)
                .hidden()
                .overlay(alignment: .leading) {
                    DemoMonoLabel(name)
                }
            DemoMonoLabel(value, tint: tint ?? .primary)
                .lineLimit(1)
                .truncationMode(truncatesMiddle ? .middle : .tail)
                .minimumScaleFactor(truncatesMiddle ? 0.85 : 0.7)
        }
    }
}

// MARK: - Model

/// Runs the attempts at the download and keeps what each one sent and
/// received.
///
/// An attempt is one image task. The pipeline reports its request through
/// the probe's `willLoadData` event, the loader reports the response through
/// its hooks, and ``Wire`` ties the load to the attempt. The bytes are the
/// task's progress: what the pipeline received, which a loader behind
/// another one, such as the network conditions of the Lab, doesn't know.
@MainActor
private final class ResumableDownloadsDemoModel: ObservableObject {
    struct Attempt: Identifiable {
        enum State: Equatable {
            case loading
            case cancelled
            case failed(String)
            case finished
        }

        /// Unique among the attempts of every download, so that a load of a
        /// download that was started over reaches nothing.
        let id: Int
        /// From 1 in each download.
        let number: Int
        let pipelineNumber: Int
        let startedAt: ContinuousClock.Instant
        var sent: Sent?
        var received: Received?
        /// The bytes the pipeline had, kept ones included, and the size of
        /// the image, from the task's progress.
        var completed: Int64 = 0
        var expected: Int64 = 0
        var state: State = .loading
        var endedAt: ContinuousClock.Instant?
        /// What the task's metrics recorded, for an attempt that finished.
        var record: ImageTask.Metrics.Bytes?

        var isActive: Bool { state == .loading }

        var isFailed: Bool {
            if case .failed = state { true } else { false }
        }

        /// `true` if the attempt downloads the image from the first byte,
        /// `false` if it resumes, and `nil` while that isn't known.
        var startsFromFirstByte: Bool? {
            if let received {
                return received.statusCode != 206
            }
            return sent.map { $0.rangeStart == nil }
        }

        /// The byte the attempt starts from: where the server agreed to
        /// resume, or where the request asked to while there is no answer.
        var startOffset: Int64 {
            guard startsFromFirstByte == false else { return 0 }
            return sent?.rangeStart ?? 0
        }

        /// The bytes the pipeline kept from before, as the server agreed.
        var resumedByteCount: Int64 {
            received?.statusCode == 206 ? startOffset : 0
        }

        /// The bytes this attempt downloaded.
        var downloadedByteCount: Int64 {
            max(0, completed - resumedByteCount)
        }

        var imageByteCount: Int64? {
            received?.imageByteCount ?? (expected > 0 ? expected : nil)
        }

        var duration: TimeInterval? {
            endedAt.map { startedAt.duration(to: $0).demoTimeInterval }
        }

        /// What the pipeline keeps of the attempt if it ends now, by the
        /// rules it keeps a partial download by, and why it keeps nothing.
        var expectedKeep: (byteCount: Int64, reason: String?) {
            guard let received else {
                // Ended before the server answered: the pipeline puts back
                // what the attempt started with.
                return (startOffset, startOffset > 0 ? nil : "no response")
            }
            guard completed > 0 else {
                return (0, "no bytes arrived")
            }
            guard received.statusCode == 200 || received.statusCode == 206 else {
                return (0, "status \(received.statusCode)")
            }
            guard received.acceptRanges?.lowercased() == "bytes" else {
                return (0, "no Accept-Ranges")
            }
            guard received.hasValidator else {
                return (0, "no validator")
            }
            if let length = received.contentLength.flatMap({ Int64($0) }), completed >= length {
                return (0, "more bytes than Content-Length")
            }
            return (completed, nil)
        }

        var status: String {
            let percent = imageByteCount.map { " \(Int(Double(completed) / Double(max(1, $0)) * 100))%" } ?? ""
            switch state {
            case .loading:
                guard sent != nil else { return "waiting" }
                return (startsFromFirstByte == false ? "resuming" : "downloading") + percent
            case .cancelled:
                return completed > 0 ? "cancelled at" + percent : "cancelled"
            case .failed(let reason):
                return "failed · \(reason)"
            case .finished:
                let from = resumedByteCount > 0 ? "resumed, " : ""
                return from + "done" + (duration.map { String(format: " in %.1f s", $0) } ?? "")
            }
        }

        var statusColor: Color? {
            switch state {
            case .loading: .blue
            case .cancelled: .orange
            case .failed: .red
            case .finished: .green
            }
        }
    }

    /// The request as the pipeline's delegate saw it.
    struct Sent {
        let path: String
        let host: String
        let range: String?
        let ifRange: String?
        /// `N` of `bytes=N-`.
        let rangeStart: Int64?

        init(_ request: URLRequest) {
            let url = request.url
            path = url?.lastPathComponent ?? "–"
            host = url.map { url in
                let host = url.host() ?? "–"
                return DemoFixture.isFixture(url) ? "\(host) (the fixture loader)" : host
            } ?? "–"
            range = request.value(forHTTPHeaderField: "Range")
            ifRange = request.value(forHTTPHeaderField: "If-Range")
            rangeStart = range.flatMap { range in
                guard range.hasPrefix("bytes="), range.hasSuffix("-") else { return nil }
                return Int64(range.dropFirst("bytes=".count).dropLast())
            }
        }
    }

    /// The response as the pipeline got it.
    struct Received {
        let statusCode: Int
        let contentLength: String?
        let contentRange: String?
        let entityTag: String?
        let lastModified: String?
        let acceptRanges: String?
        /// The size of the whole image: the length of a 200, or the total a
        /// 206 names in its `Content-Range`.
        let imageByteCount: Int64?

        init(_ response: URLResponse) {
            let http = response as? HTTPURLResponse
            statusCode = http?.statusCode ?? 0
            // Case-insensitive, where `allHeaderFields` is not.
            contentLength = http?.value(forHTTPHeaderField: "Content-Length")
            contentRange = http?.value(forHTTPHeaderField: "Content-Range")
            entityTag = http?.value(forHTTPHeaderField: "ETag")
            lastModified = http?.value(forHTTPHeaderField: "Last-Modified")
            acceptRanges = http?.value(forHTTPHeaderField: "Accept-Ranges")
            if let contentRange, let total = contentRange.split(separator: "/").last {
                imageByteCount = Int64(total)
            } else {
                imageByteCount = response.expectedContentLength > 0 ? response.expectedContentLength : nil
            }
        }

        var statusLine: String {
            switch statusCode {
            case 200: "200 OK"
            case 206: "206 Partial Content"
            default: "\(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized)"
            }
        }

        var hasValidator: Bool {
            entityTag != nil || lastModified != nil
        }
    }

    /// The attempt a run of bytes of the image came from.
    struct Segment: Identifiable, Equatable {
        let attemptNumber: Int
        let lowerBound: Int64
        let upperBound: Int64

        var id: Int { attemptNumber }
        var byteCount: Int64 { upperBound - lowerBound }
    }

    /// What the download cost, over its attempts.
    struct Figures {
        var imageByteCount: Int64?
        var pixelSize: String?
        var downloadedByteCount: Int64 = 0
        var resumedByteCount: Int64 = 0
        /// The bytes downloaded that the image doesn't use: the ones an
        /// attempt downloaded again.
        var wastedByteCount: Int64 = 0
        /// The attempts the image is made of, in the order of its bytes.
        var segments: [Segment] = []

        var fraction: Double? {
            guard let imageByteCount, imageByteCount > 0 else { return nil }
            return min(1, Double(segments.last?.upperBound ?? 0) / Double(imageByteCount))
        }
    }

    @Published private(set) var attempts: [Attempt] = []
    @Published private(set) var image: UIImage?
    /// Whether the server's responses keep their validators.
    @Published var sendsValidators = true {
        didSet { wire.sendsValidators = sendsValidators }
    }
    /// Whether every attempt after the first runs on a pipeline of its own.
    @Published var usesNewPipeline = false

    let isOffline = DemoFixtureMode.isOffline

    private let configuration: ImagePipeline.Configuration
    private let wire: Wire
    private var pipeline: ImagePipeline
    private var pipelineNumber = 1
    private var task: ImageTask?
    private var observer: Task<Void, Never>?
    /// The image of the download, read when it starts.
    private var url = DemoImages.landscape
    /// Counts the downloads, for the `imageID` of each.
    private var downloadNumber = 1
    private var lastAttemptID = 0

    init() {
        let relay = Relay()
        let wire = Wire(relay: relay)
        var configuration = ImagePipeline.Configuration.withDataCache(name: "com.github.kean.NukeDemo.ResumableDownloads")
        // 8 KB every 100 ms: four seconds for the photo, time to cancel.
        configuration.dataLoader = PacedDataLoader(pace: .throttled(chunkSize: 8_192, interval: .milliseconds(100)), hooks: wire.hooks)
        configuration.imageCache = ImageCache()
        // Every task finishes with a record of the bytes it resumed.
        configuration.isDiagnosticsEnabled = true
        configuration.dataCache?.removeAll()
        self.configuration = configuration
        self.wire = wire
        self.pipeline = Self.makePipeline(number: 1, configuration: configuration, wire: wire)
        relay.model = self
    }

    /// A pipeline on the same configuration: the same loader and caches,
    /// and a store of partial downloads that starts empty.
    private static func makePipeline(number: Int, configuration: ImagePipeline.Configuration, wire: Wire) -> ImagePipeline {
        let label = number == 1 ? "Resumable Downloads" : "Resumable Downloads · \(number)"
        return DemoPipelineProbe.makePipeline(label, configuration: configuration, onEvent: { event in
            // Once the pipeline added the headers, right before the load.
            guard case .willLoadData(let urlRequest) = event.kind,
                  let attemptID = event.request.userInfo[attemptKey] as? Int else { return }
            wire.willLoadData(attemptID: attemptID, request: urlRequest)
        })
    }

    var isLoading: Bool {
        attempts.last?.isActive ?? false
    }

    /// Whether the last attempt ended without the image.
    var canResume: Bool {
        guard let last = attempts.last else { return false }
        return last.state == .cancelled || last.isFailed
    }

    var hasSeveralPipelines: Bool {
        attempts.contains { $0.pipelineNumber != attempts.first?.pipelineNumber }
    }

    // MARK: Actions

    func start() {
        guard attempts.isEmpty else { return }
        url = DemoImages.landscape
        begin()
    }

    func resume() {
        guard canResume else { return }
        begin()
    }

    /// Cancels the task, and keeps observing it: the progress it reported
    /// before the cancel is still on its way.
    func cancel() {
        task?.cancel()
        task = nil
        update(attempts.last?.id) { attempt in
            guard attempt.isActive else { return }
            attempt.state = .cancelled
            attempt.endedAt = .now
        }
    }

    /// Forgets the download and begins a new one: a new `imageID`, which no
    /// partial download is kept under, and empty caches.
    func startOver() {
        cancel()
        pipeline.cache.removeAll()
        downloadNumber += 1
        attempts = []
        image = nil
        url = DemoImages.landscape
        begin()
    }

    private func begin() {
        let number = attempts.count + 1
        if usesNewPipeline, number > 1 {
            pipelineNumber += 1
            pipeline = Self.makePipeline(number: pipelineNumber, configuration: configuration, wire: wire)
        }
        lastAttemptID += 1
        let id = lastAttemptID
        var request = ImageRequest(url: url)
        request.imageID = "\(url.absoluteString)#\(downloadNumber)"
        request.userInfo[attemptKey] = id
        attempts.append(Attempt(id: id, number: number, pipelineNumber: pipelineNumber, startedAt: .now))

        let task = pipeline.imageTask(with: request)
        self.task = task
        observer = Task { [weak self] in
            for await event in task.events {
                guard let self else { return }
                self.handle(event, of: task, attemptID: id)
            }
        }
    }

    // MARK: Reports

    private func handle(_ event: ImageTask.Event, of task: ImageTask, attemptID: Int) {
        switch event {
        case .progress(let progress):
            update(attemptID) { attempt in
                attempt.completed = progress.completed
                attempt.expected = progress.total
            }
        case .preview:
            break
        case .finished(let result):
            update(attemptID) { attempt in
                switch result {
                case .success:
                    attempt.state = .finished
                    attempt.completed = max(attempt.completed, attempt.expected)
                    // Written before the task finished, so it is here by now.
                    attempt.record = task.metrics?.bytes
                case .failure(.cancelled):
                    guard attempt.isActive else { return }
                    attempt.state = .cancelled
                case .failure(let error):
                    attempt.state = .failed(task.metrics?.error?.code ?? error.description)
                }
                attempt.endedAt = attempt.endedAt ?? .now
            }
            if case .success(let response) = result, attempts.last?.id == attemptID {
                image = response.image
            }
        }
    }

    fileprivate func requestWillGo(attemptID: Int, request: URLRequest) {
        update(attemptID) { $0.sent = Sent(request) }
    }

    fileprivate func responseDidArrive(attemptID: Int, response: URLResponse) {
        update(attemptID) { $0.received = Received(response) }
    }

    private func update(_ id: Int?, _ body: (inout Attempt) -> Void) {
        guard let index = attempts.firstIndex(where: { $0.id == id }) else { return }
        body(&attempts[index])
    }

    // MARK: Reading the Attempts

    func attempt(after attempt: Attempt) -> Attempt? {
        guard let index = attempts.firstIndex(where: { $0.id == attempt.id }), index + 1 < attempts.count else { return nil }
        return attempts[index + 1]
    }

    private func attempt(before attempt: Attempt) -> Attempt? {
        guard let index = attempts.firstIndex(where: { $0.id == attempt.id }), index > 0 else { return nil }
        return attempts[index - 1]
    }

    var figures: Figures {
        var figures = Figures()
        figures.imageByteCount = attempts.reversed().lazy.compactMap(\.imageByteCount).first
        for attempt in attempts {
            figures.downloadedByteCount += attempt.downloadedByteCount
            figures.resumedByteCount += attempt.resumedByteCount
        }
        // The image is made of the last attempt that started from the first
        // byte and the ones that resumed after it. Each ends where the next
        // one started: the bytes past that were dropped.
        let first = attempts.lastIndex { $0.startsFromFirstByte == true } ?? 0
        let chain = attempts.isEmpty ? [] : Array(attempts[first...])
        for (index, attempt) in chain.enumerated() {
            let lowerBound = attempt.startOffset
            var upperBound = lowerBound + attempt.downloadedByteCount
            if index + 1 < chain.count, chain[index + 1].startsFromFirstByte == false {
                upperBound = chain[index + 1].startOffset
            }
            if let imageByteCount = figures.imageByteCount {
                upperBound = min(upperBound, imageByteCount)
            }
            guard upperBound > lowerBound else { continue }
            figures.segments.append(Segment(attemptNumber: attempt.number, lowerBound: lowerBound, upperBound: upperBound))
        }
        let covered = figures.segments.last?.upperBound ?? 0
        figures.wastedByteCount = max(0, figures.downloadedByteCount - covered)
        if let cgImage = image?.cgImage {
            figures.pixelSize = "\(cgImage.width)×\(cgImage.height)"
        }
        return figures
    }

    /// Why an attempt resumed or didn't.
    func note(for attempt: Attempt) -> LocalizedStringKey? {
        guard let previous = self.attempt(before: attempt), let startsFromFirstByte = attempt.startsFromFirstByte else {
            return nil
        }
        if !startsFromFirstByte {
            guard attempt.received != nil else { return nil }
            return "Resumed: the pipeline kept \(demoByteCount(attempt.startOffset)) of attempt \(previous.number)'s download and asked for the rest, and the server sent only that."
        }
        if attempt.sent?.rangeStart != nil {
            return "The pipeline asked for the rest, but the server sent the whole image: the validator in `If-Range` no longer matched."
        }
        if previous.pipelineNumber != attempt.pipelineNumber {
            return "Not resumed: a new pipeline, and partial downloads are kept per pipeline. This one has none."
        }
        if previous.completed == 0 {
            return "Not resumed: attempt \(previous.number) ended before any bytes arrived."
        }
        if let received = previous.received {
            if !received.hasValidator {
                return "Not resumed: attempt \(previous.number)'s response had no `ETag` or `Last-Modified`, so the pipeline kept nothing."
            }
            if received.statusCode == 206, let length = received.contentLength.flatMap({ Int64($0) }), previous.completed >= length {
                return "Not resumed: attempt \(previous.number) held \(demoByteCount(previous.completed)) of the image, and the pipeline keeps a partial download only while it holds fewer bytes than the response's `Content-Length`. For a 206, that is the length of the rest: \(demoByteCount(length))."
            }
        }
        return "Not resumed: the pipeline had nothing kept for this image."
    }

    /// Takes what the pipeline and the loader report to the model: the
    /// handlers that receive them are made before the model exists.
    @MainActor
    final class Relay {
        weak var model: ResumableDownloadsDemoModel?
    }
}

/// The key of the attempt a request belongs to, in its `userInfo`.
private let attemptKey: ImageRequest.UserInfoKey = "com.github.kean.NukeDemo.attempt"

/// Carries the reports of the pipeline and the loader from their threads to
/// the model, and plays the server's part in what the responses say.
///
/// The pipeline calls `willLoadData` and then starts the load, on its actor
/// and with nothing in between, so the load that starts next belongs to the
/// attempt whose request went through `willLoadData` last.
private final class Wire: Sendable {
    private struct State {
        var sendsValidators = true
        var nextAttemptID: Int?
        /// The attempt of each load that has no response yet, by the load's
        /// ID.
        var attemptIDs: [Int: Int] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let relay: ResumableDownloadsDemoModel.Relay

    init(relay: ResumableDownloadsDemoModel.Relay) {
        self.relay = relay
    }

    var sendsValidators: Bool {
        get { state.withLock { $0.sendsValidators } }
        set { state.withLock { $0.sendsValidators = newValue } }
    }

    var hooks: DemoLoadHooks {
        DemoLoadHooks(
            didStart: { [self] load in
                state.withLock { state in
                    state.attemptIDs[load.id] = state.nextAttemptID
                    state.nextAttemptID = nil
                }
            },
            willPassResponse: { [self] load, response in
                let (attemptID, sendsValidators) = state.withLock { ($0.attemptIDs.removeValue(forKey: load.id), $0.sendsValidators) }
                let response = sendsValidators ? response : Self.removingValidators(from: response)
                if let attemptID {
                    let relay = relay
                    Task { @MainActor in relay.model?.responseDidArrive(attemptID: attemptID, response: response) }
                }
                return response
            }
        )
    }

    func willLoadData(attemptID: Int, request: URLRequest) {
        state.withLock { $0.nextAttemptID = attemptID }
        let relay = relay
        Task { @MainActor in relay.model?.requestWillGo(attemptID: attemptID, request: request) }
    }

    /// The response a server without validators would have sent.
    private static func removingValidators(from response: URLResponse) -> URLResponse {
        guard let response = response as? HTTPURLResponse, let url = response.url else {
            return response
        }
        var headers: [String: String] = [:]
        for case let (name as String, value as String) in response.allHeaderFields
        where !["etag", "last-modified"].contains(name.lowercased()) {
            headers[name] = value
        }
        return HTTPURLResponse(url: url, statusCode: response.statusCode, httpVersion: "HTTP/1.1", headerFields: headers) ?? response
    }
}

// MARK: - Helpers

/// The color of an attempt, in the bar and in the list.
private func attemptColor(_ number: Int) -> Color {
    [Color.blue, .green, .orange, .purple, .pink, .teal][(number - 1) % 6]
}
