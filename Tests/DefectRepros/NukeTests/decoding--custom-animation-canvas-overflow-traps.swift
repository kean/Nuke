// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import CoreGraphics
@testable import Nuke

// SUSPECTED BUG: `AnimatedImageSource.init(data:delays:loopCount:size:makeFrameDecoder:)`
// only rejects a canvas with `size.width > 0, size.height > 0`
// (`Sources/Nuke/Decoding/AnimatedImageSource.swift:189`). It accepts an
// infinite canvas, and a finite one whose pixel count doesn't fit in an `Int`.
// `bytesPerFrame` (`AnimatedImageSource.swift:94-96`) then traps:
// `Int(size.width)` on infinity, or the `*` on the overflow.
//
// The size is what a decoder of your own parsed out of a file header – the
// initializer exists for formats Image I/O can't read – so a damaged or
// hostile file with 32-bit dimensions (e.g. 0xFFFFFFFF × 0xFFFFFFFF) gets an
// animation the pipeline caches and hands to NukeUI, whose
// `AnimatedImageFrameStore.bytesPerFrame(for:maxPixelSize:)` reads
// `source.bytesPerFrame` as soon as a view starts playing it: the app
// crashes.
//
// Expected: no trap – either the initializer returns `nil` for a canvas that
// isn't something to play (as it does for an empty one), or `bytesPerFrame`
// saturates.
// Actual: the process traps (EXC_BREAKPOINT / "Double value cannot be
// converted to Int because it is either infinite or NaN", or "arithmetic
// overflow").
//
// Target: NukeTests. Uses exit tests, so runs on macOS.
@Suite(.timeLimit(.minutes(5)))
struct DecodingCustomAnimationCanvasBugTests {
#if os(macOS)
    @Test func hugeCanvasDoesNotTrap() async {
        await #expect(processExitsWith: .success) {
            let source = AnimatedImageSource(
                data: Data(),
                delays: [0.1, 0.1],
                size: CGSize(width: 4_294_967_295, height: 4_294_967_295),
                makeFrameDecoder: { _ in CanvasBugNoFrames() }
            )
            _ = source?.bytesPerFrame
        }
    }

    @Test func infiniteCanvasDoesNotTrap() async {
        await #expect(processExitsWith: .success) {
            let source = AnimatedImageSource(
                data: Data(),
                delays: [0.1, 0.1],
                size: CGSize(width: CGFloat.infinity, height: 8),
                makeFrameDecoder: { _ in CanvasBugNoFrames() }
            )
            _ = source?.bytesPerFrame
        }
    }
#endif
}

private struct CanvasBugNoFrames: AnimatedImageFrameDecoding {
    func decode(at index: Int) async -> CGImage? { nil }
}
