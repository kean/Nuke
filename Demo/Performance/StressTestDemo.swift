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
        VStack(spacing: 0) {
            DemoIntro("Scroll as fast as you can. Every cell starts a request and the cell it replaces cancels one. The rate limiter smooths out the bursts, and the resize processor keeps the images small.")
            ViewControllerView { StressTestViewController() }
        }
    }
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
