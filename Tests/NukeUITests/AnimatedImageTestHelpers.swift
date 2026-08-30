// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
@testable import Nuke
@testable import NukeUI

/// A clock that ticks when a test tells it to.
///
/// Playback is a pure function of the ticks it receives, so with this in place
/// the tests assert on exact frame indexes instead of sleeping and hoping.
@MainActor
final class ManualClock: AnimatedImageClock {
    var onTick: ((TimeInterval) -> Void)?
    var isPaused: Bool = true
    var preferredFrameRate: Double = 0
    private(set) var isInvalidated = false

    func invalidate() {
        isInvalidated = true
        isPaused = true
    }

    /// Advances the clock. Like a real one, it delivers nothing while paused.
    func tick(_ delta: TimeInterval) {
        guard !isPaused, !isInvalidated else { return }
        onTick?(delta)
    }
}

extension AnimatedImagePlayer.Options {
    /// A budget no frame fits in, which puts the buffer at its two-frame floor
    /// and makes the window slide.
    static var twoFrameBuffer: AnimatedImagePlayer.Options {
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = 1
        return options
    }
}

@MainActor
enum AnimatedImageTest {
    /// Builds a player driven by a clock the test owns.
    static func makePlayer(
        frameCount: Int = 4,
        delays: [TimeInterval]? = nil,
        loopCount: Int = 0,
        size: CGSize = CGSize(width: 8, height: 8),
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options()
    ) -> (player: AnimatedImagePlayer, clock: ManualClock) {
        let data = Test.animatedGIF(frameCount: frameCount, delays: delays, loopCount: loopCount, size: size)
        let source = AnimatedImageSource(data: data)!
        let clock = ManualClock()
        return (AnimatedImagePlayer(source: source, options: options, clock: clock), clock)
    }

    /// The size of one decoded frame in memory.
    ///
    /// Read from a decoded frame rather than computed from the canvas size,
    /// because Core Graphics pads the rows of a bitmap for alignment.
    static func bytesPerFrame(of player: AnimatedImagePlayer) -> Int? {
        guard let cgImage = player.image?.cgImage else { return nil }
        return cgImage.bytesPerRow * cgImage.height
    }

    /// The color of the top-left pixel, which is what tells the generated
    /// frames apart.
    static func firstPixel(of image: PlatformImage?) -> [UInt8]? {
        guard let cgImage = image?.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = pixel.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
        guard let context else { return nil }
        // Draw the image scaled down to the single pixel of the context: every
        // generated frame is a solid color, so any pixel identifies the frame.
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel
    }
}
