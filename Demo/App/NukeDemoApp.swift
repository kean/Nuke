// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import NukeVideo
import SwiftUI

@main
struct NukeDemoApp: App {
    init() {
        // A cross-fade for every image loaded into a `UIImageView` with the
        // `loadImage(with:into:)` extension. Individual calls can override it.
        ImageLoadingOptions.shared.transition = .fadeIn(duration: 0.25)

        // Teaches the shared pipeline to decode short videos. The registry is
        // consulted by the default `ImagePipeline.Configuration/makeImageDecoder`,
        // so this one line is enough to make every screen video-aware.
        ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
    }

    var body: some Scene {
        WindowGroup {
            DemoMenu()
        }
    }
}
