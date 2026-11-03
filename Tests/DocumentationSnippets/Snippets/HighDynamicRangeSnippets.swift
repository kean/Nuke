// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Customization/ImageFormats/high-dynamic-range.md`.

import SwiftUI
import NukeUI

#if !os(watchOS)
@available(iOS 17, tvOS 17, macOS 14, visionOS 1, *)
private struct HighDynamicRangeView: View {
    let url: URL

    var body: some View {
        LazyImage(url: url)
            .priority(.high)
            .allowedDynamicRange(.high)
    }
}
#endif

#if canImport(UIKit) && !os(watchOS)
import UIKit

@available(iOS 17, tvOS 17, visionOS 1, *)
@MainActor
private func loadHighDynamicRangeImage(url: URL, imageView: UIImageView) {
    var request = ImageRequest(url: url)
    request.dynamicRange = .high

    imageView.preferredImageDynamicRange = .high
    ImageLoader.load(request, into: imageView)
}
#endif
