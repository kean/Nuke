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
        ViewControllerView { ImageViewDemoViewController() }
            .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "UIImageView",
        "`loadImage(with:options:into:)` loads an image into any `UIImageView`. It prepares the view for reuse and cancels the request the view had before, so it is safe to call it directly from `cellForItemAt`.",
        code: """
        loadImage(with: request,
                  options: options,
                  into: cell.imageView)
        """,
        points: [
            .init("Options", "`ImageLoadingOptions` carries the placeholder, the failure image, the transition, the content modes, and the tint colors."),
            .init("Failure", "The first cell uses a URL that always fails, which is what puts the failure image on screen."),
            .init("Downsampling", "Every cell asks for the image at its own size. A bitmap of the full photo is many times larger, and it is the bitmap that the memory cache holds."),
            .init("Reuse", "Nothing else is needed for cell reuse: the previous image is removed and the previous request is cancelled on every call.")
        ]
    )
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
