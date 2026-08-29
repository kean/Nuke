// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI
import UIKit

/// Demonstrates loading images into `UIImageView` with the NukeUI extensions,
/// including placeholders, failure images, transitions, and cell reuse.
struct ImageViewDemo: View {
    var body: some View {
        VStack(spacing: 0) {
            DemoIntro("`loadImage(with:options:into:)` loads an image into any `UIImageView`. It prepares the view for reuse and cancels the previous request, so it is safe to call it directly from `cellForItemAt`. The first cell uses a URL that always fails to show the failure image.")
            ViewControllerView { ImageViewDemoViewController() }
        }
    }
}

private final class ImageViewDemoViewController: PhotoGridViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        itemsPerRow = 3
        photos = [DemoImages.failing] + DemoImages.photos
    }

    override func makeLoadingOptions() -> ImageLoadingOptions {
        var options = ImageLoadingOptions()
        options.placeholder = UIImage(systemName: "photo")
        options.failureImage = UIImage(systemName: "exclamationmark.triangle")
        options.transition = .fadeIn(duration: 0.33)
        options.contentModes = .init(success: .scaleAspectFill, failure: .center, placeholder: .center)
        options.tintColors = .init(success: nil, failure: .systemRed, placeholder: .tertiaryLabel)
        options.pipeline = pipeline
        return options
    }

    override func makeRequest(for url: URL, size: CGSize) -> ImageRequest {
        // Downsampling the image to the size of the cell keeps the memory
        // cache small: a bitmap of the original photo is many times larger.
        ImageRequest(url: url, processors: [.resize(size: size)])
    }
}
