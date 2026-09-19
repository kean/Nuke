// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI
import UIKit

/// Puts the pipeline under stress: thousands of cells, ten images per row, and
/// every cache disabled, so that fast scrolling starts and cancels hundreds of
/// requests per second.
///
/// This is where the rate limiter earns its keep: it protects `URLSession`
/// from the bursts of requests that a scroll view creates without adding any
/// delay when the screen is opened.
///
/// It runs on fixtures unless the picker says otherwise, so that one run
/// measures what the last one did rather than the network in between. The
/// pipeline HUD comes on with the screen, and Auto-Scroll scrolls at a fixed
/// speed for a fixed time, so that two runs – or fixtures and the network –
/// can be compared by their dropped frames and their tasks.
struct ScrollStressDemo: View {
    @State private var source = DemoImageSource.fixtures
    @State private var model = ScrollStressModel()
    /// Whether the HUD was on before the screen put it on.
    @State private var wasHUDVisible: Bool?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Images", selection: $source) {
                    ForEach(DemoImageSource.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(model.isScrolling)

                ScrollStressPanel(model: model, source: source)
            }
            .padding(16)

            // A new grid, and a new pipeline, for each source.
            ViewControllerView { ScrollStressViewController(source: source, model: model) }
                .id(source)
        }
        .onAppear {
            // Pinned while the screen is open, and put back as it was on the
            // way out, unless it was switched off here.
            let hud = DemoHUD.shared
            wasHUDVisible = hud.isVisible
            hud.isVisible = true
        }
        .onDisappear {
            if wasHUDVisible == false {
                DemoHUD.shared.isVisible = false
            }
            model.stopAutoScroll()
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            model.startWatching()
            defer { model.stopWatching() }
            await demoWaitUntilCancelled()
        }
        .task {
            guard DemoLaunchOptions.claimAutorun(for: .scrollStress) else { return }
            // Once the first screenful has loaded.
            guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
            model.startAutoScroll(source: source)
        }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Scroll Stress",
        "Scroll as fast as you can, or let Auto-Scroll do it. Every cell that appears starts a request and every cell it replaces cancels one, which is hundreds of requests a second. Nothing here is cached and nothing is coalesced, so each one goes through the entire pipeline.",
        code: """
        ImagePipeline {
            $0.imageCache = nil
            $0.isTaskCoalescingEnabled = false
        }
        """,
        points: [
            .init("Rate limiter", "It absorbs the bursts that a scroll view creates so that `URLSession` never sees them, and it adds no delay when the screen is opened."),
            .init("Cancellation", "A request that is cancelled before it starts costs nothing. That is what makes fast scrolling survivable."),
            .init("Downsampling", "The resize processor keeps the bitmaps at the size of the cell, which is the difference between megabytes and kilobytes per image."),
            .init("Auto-Scroll", "Scrolls the grid from the top at 3,000 points a second for 10 seconds, turning at either end. A display link moves it by as far as the time since the last frame says, so a late frame jumps, as a real scroll does. Each source keeps its last run: the frames dropped, the hitch time per second, the longest frame, and the tasks the pipeline started, cancelled, and finished with an image while it ran."),
            .init("Frames", "Counted by a display link of the screen's own, apart from the HUD's: a frame that came a refresh or more late. It sees what a busy main thread costs, not what the render server drops on its own. The live figures count from the moment the screen opened, or a run started."),
            .init("HUD", "Comes on with the screen and follows its pipeline. It goes back off when you leave, if it was off before."),
            .init("Fixtures", "The default: the stand-ins for the photo stream, from memory, each 50 ms after it's asked for, so a run compares with the last one. Network loads the photos themselves, over a `DataLoader` without `URLCache`."),
            .init("Not a benchmark", "Every cache is disabled on purpose, and a simulator's frames say little about a phone's. A real app would serve most of these from memory. A run compares this build with the last one, on the same device and the same source.")
        ]
    )
}

// MARK: - Panel

/// Auto-Scroll, the live frame counts, and the last run of each source.
private struct ScrollStressPanel: View {
    let model: ScrollStressModel
    let source: DemoImageSource

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if model.isScrolling {
                    Button("Stop", systemImage: "stop.fill") {
                        model.stopAutoScroll()
                    }
                } else {
                    Button("Auto-Scroll", systemImage: "play.fill") {
                        model.startAutoScroll(source: source)
                    }
                }
                DemoMonoLabel(live, tint: .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if !model.results.isEmpty {
                results
            }
        }
    }

    private var live: String {
        let figures = model.live
        let rate = figures.framesPerSecond.map { "\(Int($0.rounded())) fps" } ?? "– fps"
        let prefix = model.isScrolling ? demoPad(demoSeconds(model.elapsed), to: 5) : "live"
        return "\(prefix) · \(rate) · \(figures.droppedFrameCount) dropped · \(demoDelay(figures.longestFrame)) worst"
    }

    private var results: some View {
        Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 2) {
            GridRow {
                Text("last run")
                    .gridColumnAlignment(.leading)
                Text("dropped")
                Text("ms/s")
                Text("worst")
                Text("tasks")
                Text("cancel")
                Text("images")
            }
            .foregroundStyle(.secondary)
            ForEach(DemoImageSource.allCases) { source in
                if let result = model.results[source] {
                    GridRow {
                        Text(source.title.lowercased())
                        Text(result.frames.droppedFrameCount.formatted())
                            .foregroundStyle(result.frames.droppedFrameCount > 0 ? .orange : .primary)
                        Text(String(format: "%.1f", (result.frames.hitchTimeRatio ?? 0) * 1000))
                        Text(demoDelay(result.frames.longestFrame))
                        Text(result.startedTaskCount.formatted())
                        Text(result.cancelledTaskCount.formatted())
                        Text(result.imageCount.formatted())
                    }
                }
            }
        }
        .font(.system(.caption2, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

// MARK: - Model

/// The screen's frame counter, Auto-Scroll, and the last run of each source.
@MainActor @Observable
private final class ScrollStressModel {
    /// Points per second.
    static let speed: CGFloat = 3000
    static let duration: TimeInterval = 10

    /// The display since the screen opened or a run started.
    private(set) var live = DemoDisplayMonitor.Figures()
    private(set) var isScrolling = false
    /// How long the run in progress has scrolled.
    private(set) var elapsed: TimeInterval = 0
    /// The last run of each source.
    private(set) var results: [DemoImageSource: Result] = [:]

    /// The grid on screen; a new one comes with each source.
    @ObservationIgnored weak var grid: ScrollStressViewController?
    @ObservationIgnored private let monitor = DemoDisplayMonitor()
    @ObservationIgnored private var samplingTask: Task<Void, Never>?
    /// The source of the run in progress, and its pipeline's figures when
    /// it started.
    @ObservationIgnored private var run: (source: DemoImageSource, baseline: DemoPipelineDiagnostics)?

    struct Result {
        let frames: DemoDisplayMonitor.Figures
        let startedTaskCount: Int
        let cancelledTaskCount: Int
        let imageCount: Int
    }

    /// Counts frames, and reads them four times a second, while the screen
    /// is on display.
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
        if isScrolling, let grid {
            elapsed = grid.autoScrollElapsed
        }
    }

    func startAutoScroll(source: DemoImageSource) {
        guard !isScrolling, let grid, let baseline = DemoPipelineProbe.diagnostics(for: grid.pipeline) else { return }
        run = (source, baseline)
        monitor.reset()
        live = monitor.figures
        elapsed = 0
        isScrolling = true
        grid.startAutoScroll(speed: Self.speed, duration: Self.duration) { [weak self] duration in
            self?.didFinishAutoScroll(duration: duration)
        }
    }

    func stopAutoScroll() {
        grid?.stopAutoScroll()
    }

    private func didFinishAutoScroll(duration: TimeInterval) {
        isScrolling = false
        guard let run, let grid, let figures = DemoPipelineProbe.diagnostics(for: grid.pipeline) else { return }
        self.run = nil
        let frames = monitor.figures
        results[run.source] = Result(
            frames: frames,
            startedTaskCount: figures.createdTaskCount - run.baseline.createdTaskCount,
            cancelledTaskCount: figures.cancelledTaskCount - run.baseline.cancelledTaskCount,
            imageCount: figures.succeededTaskCount - run.baseline.succeededTaskCount
        )
        live = frames
        elapsed = duration
    }
}

// MARK: - Grid

private final class ScrollStressViewController: DemoAutoScrollGridViewController {
    private let source: DemoImageSource
    private let model: ScrollStressModel

    init(source: DemoImageSource, model: ScrollStressModel) {
        self.source = source
        self.model = model
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        itemsPerRow = 10
        model.grid = self

        // Nothing is cached and nothing is coalesced: every cell has to go
        // through the entire pipeline.
        let source = source
        pipeline = DemoPipelineProbe.makePipeline("Scroll Stress · \(source.title)") {
            switch source {
            case .fixtures:
                // A fixed wait stands in for the network's, so a cell that
                // scrolls away mid-load is cancelled the way it would be.
                $0.dataLoader = DemoFixtureLoader(pace: .init(latency: .milliseconds(50)))
            case .network:
                $0.dataLoader = DataLoader(configuration: {
                    let configuration = URLSessionConfiguration.default
                    configuration.urlCache = nil
                    return configuration
                }())
            }
            $0.imageCache = nil
            $0.isTaskCoalescingEnabled = false
        }

        photos = (0..<20).flatMap { _ in DemoImages.photos(from: source) }
    }

    override func makeRequest(for url: URL, size: CGSize) -> ImageRequest {
        ImageRequest(url: url, processors: [.resize(size: size)])
    }
}
