// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import os
import SwiftUI
import UIKit

/// Demonstrates decompression: what `isDecompressionEnabled` and
/// `isUsingPrepareForDisplay` save the main thread, measured in frames.
///
/// ```swift
/// ImagePipeline {
///     $0.isDecompressionEnabled = true // the default
///     $0.isUsingPrepareForDisplay = true
/// }
/// ```
///
/// `UIImage(data:)` doesn't decode a JPEG. It reads the header and leaves the
/// pixels until Core Animation needs them, when a view first draws the image,
/// on the main thread. Nuke draws each image into a bitmap on its
/// decompressing queue instead, before the view gets it.
///
/// The grid shows the demo's 12 MP JPEG fixture in every cell, each under a
/// URL of its own, at full size: a thumbnail, which the last configuration
/// asks for, is decoded at the size of the cell, and has nothing left to
/// decompress. Auto-Scroll scrolls the grid at a fixed speed for a fixed time
/// on a new pipeline for each configuration, whose memory cache starts
/// empty, so every image is decoded fresh, and the screen's own
/// ``DemoDisplayMonitor`` counts the frames the main thread missed. Each
/// configuration keeps its last run, next to the probe's decompression
/// figures and the footprint's peak.
///
/// A decoded 12 MP image takes 46 MB, whichever thread decoded it, so the
/// grid holds no more than a phone can: two images to a row (three on an
/// iPad), a memory cache of four, and a cell that lets go of its image as
/// it leaves the screen. Without the last, decompression off peaked at over
/// 4 GB on the simulator: UIKit kept a hundred cells for reuse, each with
/// its image.
struct DecompressionDemo: View {
    @State private var model = DecompressionDemoModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            DecompressionPanel(model: model)
                .padding(16)
            Divider()
            ViewControllerView { DecompressionGridViewController(model: model) }
        }
        .onDisappear {
            model.stop()
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            model.startWatching()
            defer { model.stopWatching() }
            await demoWaitUntilCancelled()
        }
        .task {
            guard DemoLaunchOptions.current.autoruns, !Autorun.hasRun else { return }
            Autorun.hasRun = true
            // The fixture is made on first use, which the first run
            // shouldn't wait on.
            _ = try? await DemoFixtureStore.shared.entry(for: .largeJPEG)
            model.runAll()
        }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Decompression",
        "A JPEG stays compressed until something draws it, and what draws it first is Core Animation, on the main thread, as the cell comes on screen. Nuke decodes each image into a bitmap on a background queue before it hands it over. Pick a configuration and run Auto-Scroll over a grid of 12 MP images: the frames the main thread missed, and the memory the app took, say what each one costs.",
        code: """
        ImagePipeline {
            // The default on iOS, tvOS, and visionOS
            $0.isDecompressionEnabled = true
            // UIImage.preparingForDisplay() in place of Core Graphics
            $0.isUsingPrepareForDisplay = true
        }

        // One request
        ImageRequest(url: url, options: [.skipDecompression])

        // Or skip it: decoded at the size it is shown at
        var request = ImageRequest(url: url)
        request.thumbnail = .init(size: cell.bounds.size)
        """,
        points: [
            .init("Why", "`UIImage(data:)` reads a JPEG's header and nothing more. The pixels are decoded when Core Animation first needs them – when the frame with the image in it is committed, on the main thread – and a 12 MP JPEG takes tens of milliseconds, several frames' worth. A decompressed image arrives as a bitmap, and the view only has to show it."),
            .init("Off", "`isDecompressionEnabled = false`: every image reaches the view as soon as its header is read, and the main thread decodes it on the way to the screen. The pipeline asks its delegate's `shouldDecompress` and hears no, which the HUD counts as declined."),
            .init("On", "The default. Each image is drawn into a bitmap with Core Graphics on `imageDecompressingQueue`, two at a time. A cell that scrolls away before its turn is cancelled and costs nothing. An image arrives a little later, and the main thread doesn't pay for it."),
            .init("Prepare", "`isUsingPrepareForDisplay = true` swaps the drawing for `UIImage.preparingForDisplay()`, the system's own, on the same queue."),
            .init("Thumbnail", "`ImageRequest.thumbnail` has Image I/O decode the image at the size of the cell, on the decoding queue: a sliver of the pixels, and a bitmap already, so there is nothing to decompress. For a grid, that is the bigger saving. Decompression is what is left to do for images shown at full size."),
            .init("What isn't decompressed", "Thumbnails, and images a processor made, which are drawn already. Requests with `.skipDecompression`. An image served from the memory cache, which was decompressed when it was stored. Everything on macOS, where it is off by default. A delegate decides per response in `shouldDecompress(response:for:pipeline:)`, and can do it its own way in `decompress(response:request:pipeline:)`."),
            .init("Memory", "A decoded image is its bitmap, 4 bytes a pixel: 46 MB for 12 MP, which is what the memory cache counts it at. It costs that whether Nuke decompresses it or not: with decompression off, Image I/O keeps the pixels it decoded for Core Animation with the image for as long as the image lives. On, the cost is paid before the image is on screen. The memory cache here holds four, `ImageCache(countLimit: 4)`; the default limit, up to 768 MB, would hold 16."),
            .init("Cells", "A cell waiting to be reused keeps its image until it is. With decompression off, the main thread was so busy decoding that UIKit's cell prefetching kept making new cells rather than reusing old ones: a hundred of them, each with its image, over 4 GB on the simulator. So a cell here lets go of its image as it leaves the screen, in `collectionView(_:didEndDisplaying:forItemAt:)`, and the grid has two images to a row, three on an iPad: 8 or 12 on screen at most."),
            .init("Disk cache", "The disk cache keeps the downloaded data by default, and a disk hit is decoded and decompressed again. `.storeEncodedImages` stores the decompressed image instead, encoded again as a JPEG at 0.8, so a disk hit decodes that: often larger than the original for a photo, and a still for an animation or a video, whose first frame is all it keeps."),
            .init("The run", "Auto-Scroll scrolls the grid from the top at 1,000 points a second for 6 seconds. Before each run, the screen builds a pipeline with the configuration and an empty memory cache, and waits a second for the first screenful. Every cell asks for the same 12 MP JPEG fixture under a URL of its own, so each image is decoded fresh: one the memory cache already had was decompressed or drawn before, and would cost nothing. Run All runs the four in turn."),
            .init("Frames", "Counted by a display link of the screen's own, on the main thread: a frame that came a refresh or more late. It sees what decoding on the main thread costs, not what the render server drops on its own. ms/s is the time the late frames were late by, per second scrolled."),
            .init("Simulator", "The difference shows on a simulator too, but its figures are the Mac's: it decodes on the Mac's cores, and a phone takes longer over each image. The simulator also leaves the bitmaps Nuke draws with Core Graphics out of the footprint, so On peaks lower than Prepare, though its images are as large. Compare runs on the same device, not a simulator with a phone."),
            .init("Figures", "Images are the tasks that finished with one while the grid scrolled. Decode and decompress are the probe's averages and slowest, from the pipeline's decoder and its `decompress` call. Peak is the app's highest footprint while the grid scrolled, the figure the system terminates an app over, read every 20 ms. The HUD shows the same figures live, and how often `shouldDecompress` said no.")
        ]
    )
}

/// Runs on its own only once per launch, not each time the screen comes
/// back.
@MainActor
private enum Autorun {
    static var hasRun = false
}

// MARK: - Configurations

/// What the pipeline, or the request, is set to for a run.
private enum DecompressionSetting: CaseIterable, Identifiable {
    case off
    case coreGraphics
    case prepareForDisplay
    case thumbnail

    var id: Self { self }

    /// The name on the picker and in the results.
    var title: String {
        switch self {
        case .off: "Off"
        case .coreGraphics: "On"
        case .prepareForDisplay: "Prepare"
        case .thumbnail: "Thumbnail"
        }
    }

    /// What the setting is, in code.
    var code: String {
        switch self {
        case .off: "isDecompressionEnabled = false"
        case .coreGraphics: "isDecompressionEnabled = true // default"
        case .prepareForDisplay: "isUsingPrepareForDisplay = true"
        case .thumbnail: "request.thumbnail = .init(size: cell)"
        }
    }

    var summary: String {
        switch self {
        case .off: "Decoded by Core Animation, on the main thread, as each cell first draws."
        case .coreGraphics: "Drawn into a bitmap with Core Graphics on the decompressing queue."
        case .prepareForDisplay: "UIImage.preparingForDisplay() on the decompressing queue."
        case .thumbnail: "Decoded at the cell's size on the decoding queue: nothing to decompress."
        }
    }

    var isDecompressionEnabled: Bool {
        self != .off
    }

    var isUsingPrepareForDisplay: Bool {
        self == .prepareForDisplay
    }

    var isThumbnail: Bool {
        self == .thumbnail
    }
}

// MARK: - Panel

/// The configuration, Auto-Scroll, the live frame counts, and the last run of
/// each configuration.
private struct DecompressionPanel: View {
    @Bindable var model: DecompressionDemoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Configuration", selection: $model.setting) {
                ForEach(DecompressionSetting.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(model.isRunning)

            VStack(alignment: .leading, spacing: 2) {
                DemoMonoLabel(model.setting.code, tint: .primary)
                Text(model.setting.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            HStack(spacing: 8) {
                if model.isRunning {
                    Button("Stop", systemImage: "stop.fill") {
                        model.stop()
                    }
                } else {
                    Button("Auto-Scroll", systemImage: "play.fill") {
                        model.run([model.setting])
                    }
                    Button("Run All") {
                        model.runAll()
                    }
                }
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            DemoMonoLabel(live, tint: .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // One size for every cell: each shrinking on its own, the
            // columns would read at different sizes.
            ViewThatFits(in: .horizontal) {
                results(.system(.caption2, design: .monospaced), spacing: 9)
                results(.system(size: 9.5, design: .monospaced), spacing: 6)
            }

            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
    }

    private var live: String {
        let figures = model.live
        let rate = figures.framesPerSecond.map { "\(Int($0.rounded())) fps" } ?? "– fps"
        let prefix = switch model.phase {
        case .preparing: "ready…"
        case .scrolling: demoPad(demoSeconds(model.elapsed), to: 4)
        case nil: "live"
        }
        let images = model.pipelineFigures.map { " · \($0.succeededTaskCount) images" } ?? ""
        return "\(prefix) · \(rate) · \(figures.droppedFrameCount) dropped · \(demoDelay(figures.longestFrame)) worst\(images)"
    }

    private var note: String {
        switch model.phase {
        case .preparing(let setting):
            return "\(setting.title): a new pipeline with an empty memory cache, and a second for the first screenful…"
        case .scrolling(let setting):
            return "\(setting.title): scrolling at \(Self.speed) for \(Int(DecompressionDemoModel.duration)) seconds…"
        case nil:
            return "Each run: a new pipeline with an empty memory cache, then \(Self.speed) for \(Int(DecompressionDemoModel.duration)) seconds. Compare runs on the same device."
        }
    }

    private static let speed = "\(Int(DecompressionDemoModel.speed).formatted()) pt/s"

    private func results(_ font: Font, spacing: CGFloat) -> some View {
        Grid(alignment: .trailing, horizontalSpacing: spacing, verticalSpacing: 2) {
            GridRow {
                Text("last run")
                    .gridColumnAlignment(.leading)
                Text("dropped")
                Text("ms/s")
                Text("worst")
                Text("peak")
                Text("images")
                Text("decode")
                Text("decomp")
            }
            .foregroundStyle(.secondary)
            ForEach(DecompressionSetting.allCases) { setting in
                GridRow {
                    Text(setting.title.lowercased())
                        .foregroundStyle(setting == model.setting ? .primary : .secondary)
                    if let result = model.results[setting] {
                        Text(result.frames.droppedFrameCount.formatted())
                            .foregroundStyle(result.frames.droppedFrameCount > 0 ? .orange : .primary)
                        Text(String(format: "%.0f", (result.frames.hitchTimeRatio ?? 0) * 1000))
                        Text(demoDelay(result.frames.longestFrame))
                        Text(result.footprintPeak.map { demoByteCount($0) } ?? "–")
                        Text(result.imageCount.formatted())
                        Text(Self.timing(result.decoding, showsMax: false))
                        Text(Self.timing(result.decompression, showsMax: true))
                    } else {
                        ForEach(0..<7, id: \.self) { _ in
                            Text("–")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .font(font)
        .lineLimit(1)
        .fixedSize()
    }

    /// "41/58" – the average and the slowest, in milliseconds – or a dash.
    private static func timing(_ timing: DemoPipelineDiagnostics.Timing, showsMax: Bool) -> String {
        guard timing.count > 0 else { return "–" }
        let average = String(format: "%.0f", timing.average * 1000)
        return showsMax ? "\(average)/\(String(format: "%.0f", timing.max * 1000))" : average
    }
}

// MARK: - Model

/// The screen's pipeline, its frame counter, and the runs.
@MainActor @Observable
private final class DecompressionDemoModel {
    /// Points per second.
    static let speed: CGFloat = 1000
    static let duration: TimeInterval = 6
    /// The cells in the grid: more than a run scrolls past on either device,
    /// so a run never turns back to images it has decoded.
    static let imageCount = 600

    /// The configuration the grid is showing. A pick builds a new pipeline.
    var setting = DecompressionSetting.coreGraphics {
        didSet {
            if setting != oldValue {
                apply()
            }
        }
    }

    /// The display since the configuration was picked, or the run started.
    private(set) var live = DemoDisplayMonitor.Figures()
    /// The current pipeline's figures, sampled.
    private(set) var pipelineFigures: DemoPipelineDiagnostics?
    private(set) var phase: Phase?
    /// How long the run in progress has scrolled.
    private(set) var elapsed: TimeInterval = 0
    /// The last run of each configuration.
    private(set) var results: [DecompressionSetting: Result] = [:]

    var isRunning: Bool { phase != nil }

    enum Phase: Equatable {
        /// A new pipeline is loading the first screenful.
        case preparing(DecompressionSetting)
        case scrolling(DecompressionSetting)
    }

    struct Result {
        let frames: DemoDisplayMonitor.Figures
        /// The highest footprint while the grid scrolled, or `nil` if the
        /// kernel didn't answer.
        let footprintPeak: Int?
        /// The tasks that finished with an image during the run.
        let imageCount: Int
        let decoding: DemoPipelineDiagnostics.Timing
        let decompression: DemoPipelineDiagnostics.Timing
    }

    /// The grid on screen.
    @ObservationIgnored private weak var grid: DecompressionGridViewController?
    @ObservationIgnored private var pipeline: ImagePipeline?
    @ObservationIgnored private let monitor = DemoDisplayMonitor()
    @ObservationIgnored private var samplingTask: Task<Void, Never>?
    /// The configurations still to run.
    @ObservationIgnored private var pending: [DecompressionSetting] = []
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var footprintPeak: FootprintPeak?

    /// Called by the grid once it has a collection view.
    func gridDidLoad(_ grid: DecompressionGridViewController) {
        self.grid = grid
        apply()
    }

    /// A new pipeline with the configuration and an empty memory cache, and
    /// the grid back at the top, asking it for every image.
    private func apply() {
        guard let grid else { return }
        // A cell waiting for reuse holds on to the pipeline it last loaded
        // with, and so to its memory cache, until it is reused: emptied
        // here, the images don't count against the next run.
        self.pipeline?.cache.removeAll(caches: .memory)
        let setting = setting
        let pipeline = DemoPipelineProbe.makePipeline("Decompression · \(setting.title)") {
            // The fixture, from memory, with no wait: the run measures the
            // images, not the network.
            $0.dataLoader = DemoFixtureLoader()
            // Four images, 183 MB. The default limit would keep 16 of
            // them, 732 MB, on top of the ones on screen.
            $0.imageCache = ImageCache(countLimit: 4)
            $0.isDecompressionEnabled = setting.isDecompressionEnabled
            $0.isUsingPrepareForDisplay = setting.isUsingPrepareForDisplay
        }
        self.pipeline = pipeline
        grid.show(pipeline: pipeline, isThumbnail: setting.isThumbnail)
        monitor.reset()
        live = monitor.figures
    }

    // MARK: Watching

    /// Counts frames, and reads them and the pipeline four times a second,
    /// while the screen is on display.
    func startWatching() {
        monitor.start()
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func stopWatching() {
        samplingTask?.cancel()
        samplingTask = nil
        monitor.stop()
    }

    private func sample() {
        live = monitor.figures
        pipelineFigures = pipeline.flatMap { DemoPipelineProbe.diagnostics(for: $0) }
        if case .scrolling = phase, let grid {
            elapsed = grid.autoScrollElapsed
        }
    }

    // MARK: Running

    func runAll() {
        run(DecompressionSetting.allCases)
    }

    /// Runs each configuration in turn: a new pipeline, a second for the
    /// first screenful, then Auto-Scroll.
    func run(_ settings: [DecompressionSetting]) {
        guard phase == nil, grid != nil else { return }
        pending = settings
        next()
    }

    func stop() {
        pending = []
        preparation?.cancel()
        preparation = nil
        footprintPeak = nil
        let wasScrolling = phase.map { if case .scrolling = $0 { true } else { false } } ?? false
        phase = nil
        if wasScrolling {
            grid?.stopAutoScroll()
        }
    }

    private func next() {
        guard !pending.isEmpty else {
            phase = nil
            return
        }
        let setting = pending.removeFirst()
        // Always a new pipeline, even for the configuration on screen: its
        // memory cache has the images the last scroll decoded.
        if self.setting == setting {
            apply()
        } else {
            self.setting = setting
        }
        phase = .preparing(setting)
        preparation = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.startScrolling(setting)
        }
    }

    private func startScrolling(_ setting: DecompressionSetting) {
        guard phase == .preparing(setting), let grid, let pipeline,
              let baseline = DemoPipelineProbe.diagnostics(for: pipeline) else {
            return stop()
        }
        monitor.reset()
        live = monitor.figures
        footprintPeak = FootprintPeak()
        elapsed = 0
        phase = .scrolling(setting)
        grid.startAutoScroll(speed: Self.speed, duration: Self.duration) { [weak self] elapsed in
            self?.didFinishScrolling(setting, pipeline: pipeline, baseline: baseline, elapsed: elapsed)
        }
    }

    private func didFinishScrolling(_ setting: DecompressionSetting, pipeline: ImagePipeline, baseline: DemoPipelineDiagnostics, elapsed: TimeInterval) {
        // A stopped run isn't a run: its figures cover less than the rest.
        guard phase == .scrolling(setting), elapsed >= Self.duration,
              let figures = DemoPipelineProbe.diagnostics(for: pipeline) else {
            return stop()
        }
        let frames = monitor.figures
        results[setting] = Result(
            frames: frames,
            footprintPeak: footprintPeak?.value,
            imageCount: figures.succeededTaskCount - baseline.succeededTaskCount,
            decoding: figures.decoding.since(baseline.decoding),
            decompression: figures.decompression.since(baseline.decompression)
        )
        footprintPeak = nil
        live = frames
        self.elapsed = elapsed
        next()
    }
}

private extension DemoPipelineDiagnostics.Timing {
    /// The measurements since `baseline`. The slowest stays the pipeline's
    /// own, the first screenful's included: a timing keeps no slowest per
    /// span.
    func since(_ baseline: Self) -> Self {
        var timing = self
        timing.count -= baseline.count
        timing.total -= baseline.total
        return timing
    }
}

/// The highest footprint since it was created, read every 20 ms by a task of
/// its own.
///
/// Not on the main thread, which decoding holds up for a tenth of a second
/// at a time with decompression off, and not ``DemoFootprint``'s lifetime
/// peak, which can't be started over for each run. It stops when released.
private final class FootprintPeak: Sendable {
    private let peak: OSAllocatedUnfairLock<Int?>
    private let task: Task<Void, Never>

    init() {
        let peak = OSAllocatedUnfairLock<Int?>(initialState: nil)
        self.peak = peak
        task = Task.detached(priority: .userInitiated) {
            while !Task.isCancelled {
                if let footprint = DemoFootprint.read()?.footprint {
                    peak.withLock { $0 = max($0 ?? 0, footprint) }
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    deinit {
        task.cancel()
    }

    /// The highest footprint read so far, or `nil` if the kernel hasn't
    /// answered.
    var value: Int? {
        peak.withLock { $0 }
    }
}

// MARK: - Grid

/// Every cell shows the 12 MP JPEG fixture, under a URL of its own.
private final class DecompressionGridViewController: PhotoGridViewController {
    private let model: DecompressionDemoModel
    private var isThumbnail = false
    private var autoScroll: DemoAutoScroll?
    /// The cells that let go of their image when they left the screen.
    private var clearedCells: Set<ObjectIdentifier> = []

    init(model: DecompressionDemoModel) {
        self.model = model
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // The same image under a URL of its own in each cell, so that no two
        // cells share a decode or a cache entry. The fixture loader ignores
        // the query.
        let url = DemoFixture.largeJPEG.url.absoluteString
        photos = (0..<DecompressionDemoModel.imageCount).map { URL(string: "\(url)?cell=\($0)")! }
        model.gridDidLoad(self)
    }

    override func viewWillLayoutSubviews() {
        // Up to eight cells on screen on a phone and twelve on an iPad, at
        // 46 MB each once decoded.
        itemsPerRow = view.bounds.width > 600 ? 3 : 2
        super.viewWillLayoutSubviews()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopAutoScroll()
    }

    /// Starts over on a new pipeline: back at the top, with every visible
    /// cell asking again.
    func show(pipeline: ImagePipeline, isThumbnail: Bool) {
        stopAutoScroll()
        self.pipeline = pipeline
        self.isThumbnail = isThumbnail
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false)
        collectionView.reloadData()
    }

    /// A cell waiting to be reused keeps its image until it is, and with the
    /// main thread busy decoding, UIKit's cell prefetching kept making new
    /// cells rather than reusing old ones: a hundred of them, 46 MB each. A
    /// cell that leaves the screen lets go of its image, and of a request
    /// still running.
    override func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? PhotoCell else { return }
        NukeUI.cancelRequest(for: cell.imageView)
        cell.imageView.image = nil
        clearedCells.insert(ObjectIdentifier(cell))
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = super.collectionView(collectionView, cellForItemAt: indexPath)
        clearedCells.remove(ObjectIdentifier(cell))
        return cell
    }

    /// With cell prefetching, a cell that scrolls straight back is shown
    /// again without `cellForItemAt`, so it asks again here.
    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? PhotoCell, clearedCells.remove(ObjectIdentifier(cell)) != nil else { return }
        let request = makeRequest(for: photos[indexPath.item], size: cell.bounds.size)
        loadImage(with: request, options: makeLoadingOptions(), into: cell.imageView)
    }

    override func makeRequest(for url: URL, size: CGSize) -> ImageRequest {
        var request = ImageRequest(url: url)
        if isThumbnail {
            request.thumbnail = ImageRequest.ThumbnailOptions(size: size)
        }
        return request
    }

    override func makeLoadingOptions() -> ImageLoadingOptions {
        // No transitions: an image is shown the moment it arrives.
        var options = ImageLoadingOptions()
        options.pipeline = pipeline
        return options
    }

    // MARK: Auto-Scroll

    var autoScrollElapsed: TimeInterval {
        autoScroll?.elapsed ?? 0
    }

    func startAutoScroll(speed: CGFloat, duration: TimeInterval, completion: @escaping (TimeInterval) -> Void) {
        guard autoScroll == nil else { return }
        autoScroll = DemoAutoScroll(scrollView: collectionView, speed: speed, duration: duration) { [weak self] elapsed in
            self?.autoScroll = nil
            completion(elapsed)
        }
    }

    func stopAutoScroll() {
        autoScroll?.stop()
    }
}
