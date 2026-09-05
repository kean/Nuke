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
    /// Parsing is what stands between a response arriving and the animation
    /// playing. The pipeline runs it on the decoding queue, once per decoded
    /// image, so this is neither a frame's budget nor a cost paid twice – but
    /// it is still part of the latency of every animated image loaded.
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
    /// move this number: a still image never reaches the parse.
    @Test func decodeStillImage() {
        let data = Test.data(name: "fixture", extension: "png")
        let decoder = ImageDecoders.Default()

        measure {
            for _ in 0..<20 {
                _ = try? decoder.decode(data)
            }
        }
    }

    /// What an animated image costs to decode now that the decoder also parses
    /// it. The parse used to be the first display's problem; this is where it
    /// moved to.
    @Test func decodeAnimatedImage() {
        let data = Test.data(name: "cat", extension: "gif")
        let decoder = ImageDecoders.Default()

        measure {
            for _ in 0..<20 {
                _ = try? decoder.decode(data)
            }
        }
    }
}

#endif
