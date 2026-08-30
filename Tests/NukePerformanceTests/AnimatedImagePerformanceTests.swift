// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

#if !os(watchOS)

import Foundation
import Nuke
import NukeUI
import Testing

@Suite(.serialized)
struct AnimatedImagePerformanceTests {
    /// Parsing runs on the main thread when a response arrives, so what it
    /// costs is what a scroll view pays the first time it shows an animated
    /// cell. The views go through a cache, so displaying the same image again
    /// does not pay it twice – this measures the miss.
    @Test func parseAnimatedImage() {
        let data = Test.data(name: "cat", extension: "gif")

        measure {
            for _ in 0..<100 {
                _ = AnimatedImageSource(data: data)
            }
        }
    }

    /// Decoding an image now also decides whether it is animated. The check
    /// reads the container header rather than counting frames, so it should not
    /// move this number.
    @Test func decodeStillImage() {
        let data = Test.data(name: "fixture", extension: "png")
        let decoder = ImageDecoders.Default()

        measure {
            for _ in 0..<20 {
                _ = try? decoder.decode(data)
            }
        }
    }
}

#endif
