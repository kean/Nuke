// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import SwiftUI

/// Demonstrates what a single ``ImageRequest`` can ask of the pipeline: the
/// ``ImageRequest/Options-swift.struct``, a priority, and a thumbnail in place
/// of a resize processor.
///
/// ```swift
/// var request = ImageRequest(url: url, options: [.disableMemoryCacheReads])
/// request.thumbnail = ImageRequest.ThumbnailOptions(size: CGSize(width: 300, height: 200))
/// request.priority = .high
/// ```
///
/// Every change runs the request again and reads the result off what the
/// pipeline returned: the ``ImageResponse`` and the task's
/// ``ImageTask/Metrics``. Diagnostics are on for this screen's pipeline alone,
/// which is where the list of stages under the image comes from.
///
/// The pipeline has a memory cache and a `DataCache` of its own, both emptied
/// when the screen opens, and no `URLCache`: the options reach the pipeline's
/// caches and not `URLSession`'s, and with a `URLCache` in the way half of them
/// would change nothing on screen.
struct RequestOptionsDemo: View {
    @StateObject private var model = RequestOptionsDemoModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        // The result above the options on a phone held upright, beside them
        // everywhere else, so that it stays in view while they change.
        let isStacked = horizontalSizeClass == .compact && verticalSizeClass != .compact
        let layout = isStacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        let stage = RequestOptionsStage(model: model, isCompact: horizontalSizeClass == .compact)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        layout {
            if isStacked {
                stage
            } else {
                // A phone on its side has less height than the stage needs.
                ScrollView {
                    stage
                }
            }
            Divider()
            RequestOptionsPanel(model: model)
                .frame(maxWidth: isStacked ? .infinity : 400)
        }
        .background(Color(.systemGroupedBackground))
        .task { model.runIfNeeded() }
        .onDisappear { model.cancel() }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Request Options",
        "`ImageRequest` says what one request wants from the pipeline: which caches it may use, whether to decompress, a priority, and a thumbnail. Every change runs the request again. The stages under the image are the task's `ImageTask.Metrics`: the rows appear and go away as the options change.",
        code: """
        var request = ImageRequest(
            url: url,
            options: [.disableMemoryCacheReads]
        )
        request.thumbnail = ImageRequest.ThumbnailOptions(
            size: CGSize(width: 300, height: 200)
        )
        request.priority = .high
        let image = try await pipeline.image(for: request)
        """,
        points: [
            .init("Try it", "The screen opens with both caches empty, so the first run downloads. Run again and the memory cache answers. Clear decides where the next run finds the image: Memory Cache sends it to the disk, Both to the network."),
            .init("Memory cache", "`.disableMemoryCacheReads` skips the lookup and `.disableMemoryCacheWrites` skips the store, so with the second one on, the next run has to go to the disk."),
            .init("Disk cache", "`.disableDiskCacheReads` and `.disableDiskCacheWrites` do the same for the `DataCache`, and with the default `DataCachePolicy`, `.storeOriginalData`, that's all they do. A policy that stores encoded images – `.automatic` and `.storeAll` for a resized image or a thumbnail, `.storeEncodedImages` for every image – writes them without checking `.disableDiskCacheWrites`, so with one of those the option doesn't keep an image off the disk."),
            .init("Not URLCache", "The options govern the pipeline's own caches. `URLCache` lives inside `URLSession`, and a request it can answer is answered however the options are set. This screen's pipeline has no `URLCache`, so a run that isn't served from a cache is a download. To skip `URLCache`, create the request from a `URLRequest` with a `cachePolicy`."),
            .init("reloadIgnoringCachedData", "Both Reads options at once. The request still stores what it loads."),
            .init("returnCacheDataDontLoad", "Fails with `.dataMissingInCache` rather than download. Clear Both first to see it. A thumbnail falls back to the original data on the disk. A request with a processor looks only for the processed image, which the default policy never writes to the disk, so Resize fails even with the original in both caches."),
            .init("skipDecompression", "The default decoder hands back an image that Image I/O decodes when it is first drawn, which is why the `decode` stage of a full-size image is short. The `decompress` stage draws it in the background, so the main thread doesn't have to when the image appears. The option skips that stage, and the work moves to the first draw. A resized image and a thumbnail are never decompressed, so the option changes nothing for them."),
            .init("skipDataLoadingQueue", "Starts the download without waiting for one of the data loading queue's six slots. A single request never waits, so nothing changes here. The documentation says that a request with this option gets a new download when one without it is already running. The pipeline keys downloads by URL and ignores the options, so the request joins the running download and waits wherever it waits."),
            .init("Thumbnail or resize", "Both end at 300 × 200 pt. The resize processor draws the full image smaller, which decodes all of it first. A thumbnail asks Image I/O for the smaller image directly, so the full bitmap is never made. The rows under Size compare the two. For this 1.4-megapixel photo they take about as long, and the resize passes through a 5.3 MB bitmap the thumbnail never makes – 46 MB for a 12-megapixel photo."),
            .init("Priority", "Priority decides the order of the work waiting in the pipeline's queues. A single request doesn't wait, so here it changes nothing you can see – only the priority in the task's record. Priority & Coalescing shows it at work, with a full queue.")
        ]
    )
}

// MARK: - Stage

/// The result of the last run: the image, what the pipeline says it did, and
/// the stages it went through.
private struct RequestOptionsStage: View {
    @ObservedObject var model: RequestOptionsDemoModel
    /// Puts the figures beside the image rather than under it.
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isCompact {
                HStack(alignment: .top, spacing: 12) {
                    preview
                    summary
                        .fixedSize()
                }
            } else {
                preview
                    .frame(maxWidth: 480)
                summary
            }
            actions
            stages
            DemoMonoLabel(model.totals)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var preview: some View {
        Color(.secondarySystemGroupedBackground)
            .aspectRatio(3 / 2, contentMode: .fit)
            .overlay {
                if let image = model.outcome?.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else if model.outcome?.isFailure == true {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            .overlay {
                if model.isLoading {
                    ProgressView()
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !model.isLoading, let source = model.outcome?.source {
                    DemoBadge(source.title, color: source.color, style: .overImage)
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var summary: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            ForEach(model.outcome?.summary ?? RequestOptionsDemoModel.Outcome.emptySummary) { row in
                GridRow {
                    DemoMonoLabel(row.label)
                    DemoMonoLabel(row.value, tint: row.tint ?? .primary)
                }
            }
        }
        .opacity(model.isLoading ? 0.4 : 1)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Run", systemImage: "arrow.clockwise") { model.run() }
            // Clearing doesn't run the request: it sets up where the next run
            // finds the image, before an option changes.
            Menu("Clear") {
                Button("Memory Cache") { model.clear([.memory]) }
                Button("Disk Cache") { model.clear([.disk]) }
                Button("Both", role: .destructive) { model.clear([.all]) }
            }
            Spacer(minLength: 8)
            DemoMonoLabel(model.cacheContents)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// One row per stage the task went through, in the order they started.
    ///
    /// The rows that aren't there are drawn blank, so that the block keeps its
    /// height from one run to the next and the options under it hold still.
    private var stages: some View {
        let rows = model.outcome?.stages ?? []
        return VStack(alignment: .leading, spacing: 6) {
            TimeBar(shares: model.outcome?.shares ?? [])
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                ForEach(rows) { row in
                    GridRow {
                        Circle()
                            .fill(row.category.color)
                            .frame(width: 6, height: 6)
                        DemoMonoLabel(row.name, tint: .primary)
                        DemoMonoLabel(row.detail)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        DemoMonoLabel(row.duration.map(milliseconds) ?? "–")
                            .gridColumnAlignment(.trailing)
                    }
                }
                ForEach(rows.count..<max(rows.count, RequestOptionsDemoModel.maxStageCount), id: \.self) { _ in
                    GridRow {
                        DemoMonoLabel(" ")
                    }
                }
            }
        }
        .opacity(model.isLoading ? 0.4 : 1)
    }
}

/// Where the time of the task went, by `ImageTask.Metrics.timeShares`, in the
/// colors of the stage rows.
private struct TimeBar: View {
    let shares: [ImageTask.Metrics.TimeShare]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(shares, id: \.category) { share in
                    share.category.color
                        .frame(width: proxy.size.width * share.share)
                }
            }
        }
        .frame(height: 4)
        .background(Color(.systemFill))
        .clipShape(Capsule())
    }
}

// MARK: - Panel

/// What the request asks for.
private struct RequestOptionsPanel: View {
    @ObservedObject var model: RequestOptionsDemoModel
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        List {
            Section {
                Picker("Size", selection: $model.size) {
                    ForEach(RequestOptionsDemoModel.Size.allCases) { size in
                        SizeRow(size: size, measurement: model.measurements[size])
                            .tag(size)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Size")
            } footer: {
                Text(sizeFooter)
            }

            Section {
                OptionToggle(".disableMemoryCacheReads", isOn: $model.options[contains: .disableMemoryCacheReads])
                OptionToggle(".disableMemoryCacheWrites", isOn: $model.options[contains: .disableMemoryCacheWrites])
                OptionToggle(".disableDiskCacheReads", isOn: $model.options[contains: .disableDiskCacheReads])
                OptionToggle(".disableDiskCacheWrites", isOn: $model.options[contains: .disableDiskCacheWrites])
                OptionToggle(".reloadIgnoringCachedData", isOn: $model.options[contains: .reloadIgnoringCachedData])
                OptionToggle(".returnCacheDataDontLoad", isOn: $model.options[contains: .returnCacheDataDontLoad])
            } header: {
                Text("Caches")
            } footer: {
                Text("`.reloadIgnoringCachedData` is both Reads options at once. With a processor, `.returnCacheDataDontLoad` looks only for the processed image, so Resize fails with just the original cached.")
            }

            Section {
                OptionToggle(".skipDecompression", isOn: $model.options[contains: .skipDecompression])
                OptionToggle(".skipDataLoadingQueue", isOn: $model.options[contains: .skipDataLoadingQueue])
            } header: {
                Text("Decoding and Loading")
            } footer: {
                Text("Only a full-size image is decompressed, so the first option changes only Original. A single request never waits for a data loading slot, so the second changes nothing here.")
            }

            Section {
                Picker("Priority", selection: $model.priority) {
                    ForEach(ImageRequest.Priority.demoAllCases, id: \.self) { priority in
                        Text(priority.demoName).tag(priority)
                    }
                }
                DemoLink(.priorityAndCoalescing)
            } footer: {
                Text("Priority orders the work waiting in the pipeline's queues. A single request doesn't wait, so here it changes only the priority in the task's record. Priority & Coalescing shows it at work, with twenty requests and a queue of two.")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
    }

    private var sizeFooter: LocalizedStringKey {
        let size = RequestOptionsDemoModel.targetSize
        let points = "\(Int(size.width)) × \(Int(size.height)) pt"
        let pixels = "\(Int(size.width * displayScale)) × \(Int(size.height * displayScale)) px"
        return "Every change runs the request again. Resize and Thumbnail both ask for \(points), \(pixels) here. Each row shows the bitmaps its last run made, and the time from data to an image ready to draw."
    }
}

private struct SizeRow: View {
    let size: RequestOptionsDemoModel.Size
    let measurement: RequestOptionsDemoModel.Measurement?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(size.title)
                Spacer(minLength: 8)
                if let measurement {
                    DemoMonoLabel(milliseconds(measurement.time))
                }
            }
            DemoMonoLabel(measurement?.text ?? "not loaded yet")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// A toggle labeled with the option's name as it is written in code.
private struct OptionToggle: View {
    let name: String
    @Binding var isOn: Bool

    init(_ name: String, isOn: Binding<Bool>) {
        self.name = name
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(name)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Model

@MainActor
private final class RequestOptionsDemoModel: ObservableObject {
    enum Size: CaseIterable, Identifiable {
        case original
        case resize
        case thumbnail

        var id: Self { self }

        var title: String {
            switch self {
            case .original: "Original"
            case .resize: "Resize"
            case .thumbnail: "Thumbnail"
            }
        }
    }

    /// Where the image of a run came from, by `ImageResponse.cacheType`,
    /// and for a download, by its URL: offline, a fixture answers it.
    struct Source {
        let title: String
        let color: Color

        init(_ response: ImageResponse) {
            switch response.cacheType {
            case .memory?:
                title = "Memory"
                color = .green
            case .disk?:
                title = "Disk"
                color = .blue
            case nil:
                title = DemoFixture.isFixture(response.request.url) ? "Fixture" : "Network"
                color = .orange
            }
        }
    }

    /// What a run of the request produced.
    struct Outcome {
        struct SummaryRow: Identifiable {
            let label: String
            let value: String
            var tint: Color?

            var id: String { label }
        }

        struct StageRow: Identifiable {
            let id: Int
            let name: String
            let detail: String
            let duration: TimeInterval?
            let category: ImageTask.Metrics.Category
        }

        var image: UIImage?
        var source: Source?
        var isFailure = false
        var summary: [SummaryRow]
        var stages: [StageRow] = []
        var shares: [ImageTask.Metrics.TimeShare] = []

        static let emptySummary = ["from", "took", "image", "memory", "bytes"].map {
            SummaryRow(label: $0, value: "–")
        }
    }

    /// What one size cost to get to an image ready to draw.
    struct Measurement {
        /// The full-size image a resize started from. `nil` for a resize that
        /// found the original in the memory cache, and for the sizes that
        /// don't process.
        var decoded: ImagePipeline.Diagnostics.PixelSize?
        var isOriginalFromMemory = false
        /// The image the run ended with, and what it costs in memory.
        var result: ImagePipeline.Diagnostics.PixelSize
        var resultCost: Int
        var isDecompressionSkipped = false
        /// Decoding, processing, and decompressing, measured inside the work.
        var time: TimeInterval

        var text: String {
            let result = "\(result.width)×\(result.height) \(demoByteCount(resultCost))"
            if let decoded {
                return "\(decoded.width)×\(decoded.height) \(demoByteCount(bitmapCost(decoded))) → \(result)"
            }
            if isOriginalFromMemory {
                return "original in memory → \(result)"
            }
            return isDecompressionSkipped ? "\(result) · not decompressed" : result
        }
    }

    /// A run's request, and the size it was made for.
    struct Request: Sendable {
        let size: Size
        let request: ImageRequest
    }

    /// Both processed sizes ask for this, in points.
    static let targetSize = CGSize(width: 300, height: 200)

    /// The most stages a run of this screen goes through: a resize downloaded
    /// from scratch looks up the resized image and the original in both
    /// caches, then downloads, stores, decodes, resizes, and stores again.
    static let maxStageCount = 9

    @Published var size: Size = .original {
        didSet { run() }
    }
    @Published var options: ImageRequest.Options = [] {
        didSet { run() }
    }
    @Published var priority: ImageRequest.Priority = .normal {
        didSet { run() }
    }

    @Published private(set) var outcome: Outcome?
    @Published private(set) var isLoading = false
    /// The last run of each size that did the work, rather than find the
    /// image in the memory cache.
    @Published private(set) var measurements: [Size: Measurement] = [:]
    @Published private(set) var cacheContents = " "
    /// What this screen's pipeline has done since the screen opened, as the
    /// probe counts it.
    @Published private(set) var totals = " "

    private let pipeline: ImagePipeline
    private let dataCache: DataCache?
    private var task: ImageTask?
    private var observer: Task<Void, Never>?
    private var cacheSampler: Task<Void, Never>?
    private var isStarted = false

    init() {
        var configuration = ImagePipeline.Configuration.withDataCache(name: "com.github.kean.NukeDemo.RequestOptions")
        configuration.imageCache = ImageCache()
        // Only this pipeline records: every task finishes with the record the
        // stage rows are read from.
        configuration.isDiagnosticsEnabled = true
        configuration.dataCache?.removeAll()
        dataCache = configuration.dataCache as? DataCache
        pipeline = DemoPipelineProbe.makePipeline("Request Options", configuration: configuration)
    }

    func runIfNeeded() {
        guard !isStarted else { return }
        isStarted = true
        run()
    }

    func run() {
        cancel()
        isLoading = true

        let request = makeRequest()
        let task = pipeline.imageTask(with: request.request)
        self.task = task
        observer = Task { [weak self] in
            let result: Result<ImageResponse, ImagePipeline.Error>
            do throws(ImagePipeline.Error) {
                result = .success(try await task.response)
            } catch {
                result = .failure(error)
            }
            guard let self, !Task.isCancelled else { return }
            self.didFinish(task, request: request, result: result)
        }
    }

    func cancel() {
        isLoading = false
        observer?.cancel()
        observer = nil
        task?.cancel()
        task = nil
    }

    func clear(_ caches: ImagePipeline.Cache.Caches) {
        pipeline.cache.removeAll(caches: caches)
        sampleCaches()
    }

    private func makeRequest() -> Request {
        var request = ImageRequest(url: DemoImages.landscape, priority: priority, options: options)
        switch size {
        case .original:
            break
        case .resize:
            request.processors = [.resize(size: Self.targetSize)]
        case .thumbnail:
            request.thumbnail = ImageRequest.ThumbnailOptions(size: Self.targetSize)
        }
        return Request(size: size, request: request)
    }

    private func didFinish(_ task: ImageTask, request: Request, result: Result<ImageResponse, ImagePipeline.Error>) {
        isLoading = false
        // Written before the task finished, so it is here by now.
        let metrics = task.metrics
        outcome = Self.makeOutcome(result: result, metrics: metrics, size: request.size)
        if case .success = result, let metrics,
           let measurement = Self.makeMeasurement(for: request, metrics: metrics) {
            measurements[request.size] = measurement
        }
        if let figures = DemoPipelineProbe.diagnostics(for: pipeline) {
            totals = "so far: " + [
                demoCount(figures.downloadCount, "download"),
                demoCount(figures.diskCacheHitCount, "disk read"),
                demoCount(figures.decoding.count, "decode")
            ].joined(separator: " · ")
        }
        sampleCaches()
    }

    /// Reads what the caches hold once the disk cache has written what it
    /// was given: `DataCache` keeps its changes in memory for a moment first.
    private func sampleCaches() {
        cacheSampler?.cancel()
        cacheSampler = Task { [weak self, pipeline, dataCache] in
            await dataCache?.flush()
            let caches = await DemoPipelineProbe.sampleCaches(for: pipeline)
            guard let self, !Task.isCancelled else { return }
            self.cacheContents = "\(caches.imageCacheCount) in memory · \(caches.dataCacheCount ?? 0) on disk"
        }
    }

    // MARK: Reading the Record

    private static func makeOutcome(result: Result<ImageResponse, ImagePipeline.Error>, metrics: ImageTask.Metrics?, size: Size) -> Outcome {
        let took = metrics.map { milliseconds($0.duration) } ?? "–"
        var outcome: Outcome
        switch result {
        case .success(let response):
            let source = Source(response)
            let cgImage = response.image.cgImage
            let cost = metrics?.image?.memoryCost ?? cgImage.map { $0.bytesPerRow * $0.height }
            outcome = Outcome(image: response.image, source: source, summary: [
                .init(label: "from", value: source.title.lowercased(), tint: source.color),
                .init(label: "took", value: took),
                .init(label: "image", value: cgImage.map { "\($0.width)×\($0.height) px" } ?? "–"),
                .init(label: "memory", value: cost.map(demoByteCount) ?? "–"),
                .init(label: "bytes", value: metrics.map { bytes(of: $0, cacheType: response.cacheType) } ?? "–")
            ])
        case .failure(let error):
            outcome = Outcome(isFailure: true, summary: [
                .init(label: "from", value: "failed", tint: .red),
                .init(label: "took", value: took),
                .init(label: "error", value: error.demoSummary, tint: .red),
                .init(label: "image", value: "–"),
                .init(label: "bytes", value: "–")
            ])
        }
        if let metrics {
            outcome.stages = stageRows(of: metrics, size: size)
            outcome.shares = metrics.timeShares
        }
        return outcome
    }

    /// The bytes behind the image: what was downloaded, or read from the
    /// disk. A memory cache hit has none.
    private static func bytes(of metrics: ImageTask.Metrics, cacheType: ImageResponse.CacheType?) -> String {
        switch cacheType {
        case .memory?:
            return "none"
        case .disk?:
            let read = stages(of: metrics).first { $0.kind == .diskLookup && $0.result == .hit }?.bytes
            return read.map { "\(demoByteCount($0)) from disk" } ?? "–"
        case nil:
            return metrics.bytes.map { "\(demoByteCount($0.downloaded)) down" } ?? "–"
        }
    }

    /// The stages of every job the task waited on, by when they started.
    ///
    /// `willLoadData` is left out: the pipeline records it because the demo's
    /// probe is the delegate, which an app without a delegate wouldn't see.
    private static func stageRows(of metrics: ImageTask.Metrics, size: Size) -> [Outcome.StageRow] {
        var entries: [(at: TimeInterval, row: Outcome.StageRow)] = []
        for job in metrics.jobs {
            var diskLookupCount = 0
            for stage in job.stages where stage.kind != .willLoadData {
                let subject = subject(of: stage, in: job, size: size, diskLookupIndex: diskLookupCount)
                if stage.kind == .diskLookup {
                    diskLookupCount += 1
                }
                let row = Outcome.StageRow(
                    id: entries.count,
                    name: stage.kind.rawValue,
                    detail: detail(of: stage, subject: subject),
                    duration: stage.attributedDuration ?? stage.duration,
                    category: category(of: stage.kind)
                )
                entries.append((stage.queuedAt ?? stage.startedAt ?? job.createdAt, row))
            }
        }
        // Stable, so the stages that start together keep the order of the jobs.
        return entries.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element.row)
    }

    /// Which image a cache stage was about.
    ///
    /// The record keeps a digest of the key, not what it was made of, so the
    /// subject is worked out from the job: a job with a processor handles the
    /// resized image, and the job of a thumbnail request looks up the
    /// thumbnail first and the original data after it. Everything else is
    /// about the original.
    private static func subject(of stage: ImagePipeline.Diagnostics.Stage, in job: ImagePipeline.Diagnostics.Job, size: Size, diskLookupIndex: Int) -> String {
        if !job.processors.isEmpty {
            return "resized"
        }
        if size == .thumbnail, job.kind == .loadImage, stage.kind != .diskLookup || diskLookupIndex == 0 {
            return "thumbnail"
        }
        return "original"
    }

    private static func detail(of stage: ImagePipeline.Diagnostics.Stage, subject: String) -> String {
        switch stage.kind {
        case .memoryLookup:
            return "\(subject) · \(stage.result?.rawValue ?? "–")"
        case .diskLookup:
            guard stage.result == .hit else {
                return "\(subject) · \(stage.result?.rawValue ?? "–")"
            }
            return "\(subject) · hit · \(stage.bytes.map(demoByteCount) ?? "–")"
        case .download:
            var text = stage.bytes.map(demoByteCount) ?? "–"
            if let wait = stage.queueWait, wait >= 0.001 {
                text += " · waited \(milliseconds(wait))"
            }
            return text
        case .diskStore:
            return "\(subject) · \(stage.bytes.map(demoByteCount) ?? "not stored")"
        case .memoryStore:
            return subject
        case .decode, .process, .decompress:
            guard let pixels = stage.pixels else { return "" }
            return "\(pixels.width)×\(pixels.height) · \(demoByteCount(bitmapCost(pixels)))"
        case .rateLimit:
            return "held back"
        case .willLoadData, .unknown:
            return ""
        @unknown default:
            return ""
        }
    }

    /// The category `ImageTask.Metrics.timeShares` puts a stage in, so a row
    /// and its share of the bar have the same color.
    private static func category(of kind: ImagePipeline.Diagnostics.Stage.Kind) -> ImageTask.Metrics.Category {
        switch kind {
        case .download: .network
        case .rateLimit: .rateLimit
        case .process: .process
        case .decompress: .decompress
        case .decode: .decode
        case .memoryLookup, .diskLookup, .memoryStore, .diskStore: .cache
        case .willLoadData, .unknown: .other
        @unknown default: .other
        }
    }

    /// What it cost to get from data to the image the run returned, if the
    /// run did the work. A run served by the memory cache didn't, and leaves
    /// the last measurement of its size as it was.
    private static func makeMeasurement(for request: Request, metrics: ImageTask.Metrics) -> Measurement? {
        let size = request.size
        let all = stages(of: metrics).filter { $0.isProgressive != true }
        let decode = all.last { $0.kind == .decode }
        let process = all.last { $0.kind == .process }
        guard decode != nil || process != nil,
              let image = metrics.image,
              let cost = image.memoryCost else {
            return nil
        }
        let workKinds: [ImagePipeline.Diagnostics.Stage.Kind] = [.decode, .process, .decompress]
        let work = all.filter { workKinds.contains($0.kind) }
        return Measurement(
            decoded: size == .resize ? decode?.pixels : nil,
            isOriginalFromMemory: size == .resize && decode == nil,
            result: ImagePipeline.Diagnostics.PixelSize(width: image.width, height: image.height),
            resultCost: cost,
            isDecompressionSkipped: size == .original && request.request.options.contains(.skipDecompression),
            time: work.reduce(0) { $0 + ($1.workDuration ?? $1.duration ?? 0) }
        )
    }

    private static func stages(of metrics: ImageTask.Metrics) -> [ImagePipeline.Diagnostics.Stage] {
        metrics.jobs.flatMap(\.stages)
    }
}

// MARK: - Helpers

extension ImageRequest.Options {
    /// Whether every option in `option` is set, as a binding a toggle can
    /// write: on adds them all, off removes them all.
    fileprivate subscript(contains option: ImageRequest.Options) -> Bool {
        get { isSuperset(of: option) }
        set {
            if newValue {
                formUnion(option)
            } else {
                subtract(option)
            }
        }
    }
}

extension ImageTask.Metrics.Category {
    fileprivate var color: Color {
        switch self {
        case .network: .blue
        case .queue, .rateLimit: .gray
        case .process: .purple
        case .decompress: .pink
        case .decode: .orange
        case .cache: .green
        case .other: Color(.systemGray3)
        @unknown default: Color(.systemGray3)
        }
    }
}

/// What a bitmap of this size costs at 4 bytes a pixel, which is what a
/// decoded JPEG or PNG takes.
private func bitmapCost(_ pixels: ImagePipeline.Diagnostics.PixelSize) -> Int {
    pixels.width * pixels.height * 4
}

private func milliseconds(_ seconds: TimeInterval) -> String {
    let milliseconds = seconds * 1000
    return milliseconds < 10 ? String(format: "%.1f ms", milliseconds) : String(format: "%.0f ms", milliseconds)
}
