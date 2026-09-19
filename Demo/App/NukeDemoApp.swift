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

        // Every pipeline the demo builds has a `DemoPipelineProbe` for a
        // delegate. It counts what the pipeline does and, when the app is
        // launched with `NUKE_DIAGNOSTICS_ENABLED` set, logs a timeline of
        // every task to Console.
        ImagePipeline.shared = DemoPipelineProbe.makePipeline("Shared", configuration: .withURLCache)
    }

    var body: some Scene {
        WindowGroup {
            DemoMenu()
        }
    }
}
