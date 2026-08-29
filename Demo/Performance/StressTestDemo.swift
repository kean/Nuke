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
struct StressTestDemo: View {
    var body: some View {
        ViewControllerView { StressTestViewController() }
            .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Stress Test",
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
            .init("Not a benchmark", "Every cache is disabled on purpose. A real app would serve most of these from memory.")
        ]
    )
}

private final class StressTestViewController: PhotoGridViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        itemsPerRow = 10

        // Nothing is cached and nothing is coalesced: every cell has to go
        // through the entire pipeline.
        pipeline = ImagePipeline {
            $0.dataLoader = DataLoader(configuration: {
                let configuration = URLSessionConfiguration.default
                configuration.urlCache = nil
                return configuration
            }())
            $0.imageCache = nil
            $0.isTaskCoalescingEnabled = false
        }

        photos = (0..<20).flatMap { _ in DemoImages.photos }
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
