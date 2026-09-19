// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI
import UIKit

/// Puts the pipeline under stress: ten images per row, with every cache
/// disabled, so that fast scrolling starts and cancels hundreds of requests a
/// second. Auto-Scroll makes the same scroll on every run, so two builds
/// compare by their dropped frames.
struct ScrollStressDemo: View {
    @State private var model = ScrollStressModel()
    /// Whether the HUD was on before the screen put it on.
    @State private var wasHUDVisible: Bool?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if model.isScrolling {
                    Button("Stop", systemImage: "stop.fill") { model.grid?.stopAutoScroll() }
                } else {
                    Button("Auto-Scroll", systemImage: "play.fill") { model.startAutoScroll() }
                }
                DemoMonoLabel(model.liveText, tint: .primary)
                DemoMonoLabel(model.lastRun ?? "last run · –")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            ViewControllerView { [model] in
                let grid = ScrollStressViewController()
                model.grid = grid
                return grid
            }
        }
        .onAppear {
            // On while the screen is open, and back off on the way out if it
            // was off before.
            wasHUDVisible = DemoHUD.shared.isVisible
            DemoHUD.shared.isVisible = true
        }
        .onDisappear {
            if wasHUDVisible == false {
                DemoHUD.shared.isVisible = false
            }
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await model.watchUntilCancelled()
        }
        .task {
            // Once the first screenful has loaded.
            guard DemoLaunchOptions.claimAutorun(for: .scrollStress),
                  (try? await Task.sleep(for: .seconds(1))) != nil else { return }
            model.startAutoScroll()
        }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Scroll Stress",
        "Scroll as fast as you can, or let Auto-Scroll do it. Every cell that appears starts a request and every cell it replaces cancels one. Nothing is cached or coalesced, so each request goes through the entire pipeline.",
        code: """
        ImagePipeline {
            $0.imageCache = nil
            $0.isTaskCoalescingEnabled = false
        }
        """,
        points: [
            .init("Fixtures", "The images are served from memory 50 ms after they're asked for, so a run measures the pipeline rather than the network, and a cell that scrolls away mid-load is cancelled."),
            .init("Auto-Scroll", "3,000 points a second for 10 seconds, turning at either end. A late frame jumps, as a real scroll does."),
            .init("Frames", "A frame a refresh or more late is dropped. The live line counts from the moment the screen opened or a run started."),
            .init("Not a benchmark", "A simulator's frames say little about a phone's. A run compares this build with the last one on the same device.")
        ]
    )
}

/// The screen's frame counter and Auto-Scroll.
@MainActor @Observable
private final class ScrollStressModel {
    private(set) var isScrolling = false
    private(set) var liveText = ""
    private(set) var lastRun: String?

    @ObservationIgnored weak var grid: ScrollStressViewController?
    @ObservationIgnored private let monitor = DemoDisplayMonitor()

    /// Counts frames, and reads them four times a second, for as long as the
    /// calling task runs.
    func watchUntilCancelled() async {
        monitor.start()
        defer { monitor.stop() }
        while !Task.isCancelled {
            let figures = monitor.figures
            let fps = figures.framesPerSecond.map { "\(Int($0.rounded()))" } ?? "–"
            let prefix = isScrolling ? demoSeconds(grid?.autoScrollElapsed ?? 0) : "live"
            liveText = "\(prefix) · \(fps) fps · \(figures.droppedFrameCount) dropped · \(demoDelay(figures.longestFrame)) worst"
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    func startAutoScroll() {
        guard !isScrolling, let grid, let baseline = DemoPipelineProbe.diagnostics(for: grid.pipeline) else { return }
        monitor.reset()
        isScrolling = true
        grid.startAutoScroll(speed: 3000, duration: 10) { [weak self, weak grid] _ in
            guard let self else { return }
            isScrolling = false
            let frames = monitor.figures
            let tasks = (grid.flatMap { DemoPipelineProbe.diagnostics(for: $0.pipeline) }?.createdTaskCount ?? 0) - baseline.createdTaskCount
            lastRun = "last run · \(frames.droppedFrameCount) dropped · \(demoDelay(frames.longestFrame)) worst · \(tasks) tasks"
        }
    }
}

private final class ScrollStressViewController: DemoAutoScrollGridViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        itemsPerRow = 10
        pipeline = DemoPipelineProbe.makePipeline("Scroll Stress") {
            $0.dataLoader = DemoFixtureLoader(pace: .init(latency: .milliseconds(50)))
            $0.imageCache = nil
            $0.isTaskCoalescingEnabled = false
        }
        photos = (0..<20).flatMap { _ in DemoFixture.photos.map(\.url) }
    }

    override func makeRequest(for url: URL, size: CGSize) -> ImageRequest {
        ImageRequest(url: url, processors: [.resize(size: size)])
    }
}
