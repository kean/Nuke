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
/// measures what the last one did rather than the network in between.
struct ScrollStressDemo: View {
    @State private var source = DemoImageSource.fixtures

    var body: some View {
        VStack(spacing: 0) {
            Picker("Images", selection: $source) {
                ForEach(DemoImageSource.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(16)

            // A new grid, and a new pipeline, for each source.
            ViewControllerView { ScrollStressViewController(source: source) }
                .id(source)
        }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Scroll Stress",
        "Scroll as fast as you can. Every cell that appears starts a request and every cell it replaces cancels one, which is hundreds of requests a second. Nothing here is cached and nothing is coalesced, so each one goes through the entire pipeline.",
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
            .init("Fixtures", "The default: the stand-ins for the photo stream, from memory, each 50 ms after it's asked for, so a run compares with the last one. Network loads the photos themselves, over a `DataLoader` without `URLCache` – unless the demo is offline, when fixtures answer those too."),
            .init("Not a benchmark", "Every cache is disabled on purpose. A real app would serve most of these from memory.")
        ]
    )
}

private final class ScrollStressViewController: PhotoGridViewController {
    private let source: DemoImageSource

    init(source: DemoImageSource) {
        self.source = source
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        itemsPerRow = 10

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

    override func makeLoadingOptions() -> ImageLoadingOptions {
        // No transitions: they get in the way of seeing the throughput.
        var options = ImageLoadingOptions()
        options.pipeline = pipeline
        return options
    }
}
