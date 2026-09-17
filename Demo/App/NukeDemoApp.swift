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

        if DemoLaunchOptions.current.isDeterministic {
            Self.prepareDeterministicLaunch()
        }
    }

    /// Takes away what makes one launch look different from the last, for
    /// `-demoDeterministic 1`: the offline switch is already on (see
    /// ``DemoFixtureMode``), and this empties the disk caches a previous run
    /// filled and drops the fade, whose frame a screenshot would catch at
    /// random.
    ///
    /// Every `DataCache` the demo creates is named
    /// `com.github.kean.NukeDemo.<screen>`, and none exists yet.
    private static func prepareDeterministicLaunch() {
        ImageLoadingOptions.shared.transition = nil
        DataLoader.sharedUrlCache.removeAllCachedResponses()
        let fileManager = FileManager.default
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let names = try? fileManager.contentsOfDirectory(atPath: caches.path) else {
            return
        }
        for name in names where name.hasPrefix("com.github.kean.NukeDemo.") {
            try? fileManager.removeItem(at: caches.appendingPathComponent(name))
        }
    }

    var body: some Scene {
        WindowGroup {
            DemoMenu()
        }
    }
}
