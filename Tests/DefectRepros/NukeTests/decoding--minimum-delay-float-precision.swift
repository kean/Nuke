// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Nuke

// SUSPECTED BUG: `AnimatedImageSource.minimumDelay` is documented as "Delays
// below this value are replaced with `defaultDelay`: `0.011`", so a frame that
// asks for exactly 11 ms must keep it. Image I/O reports the APNG (and WebP,
// HEICS) delays as 32-bit floats: 11 ms comes back as `Float(0.011)`, which is
// 0.010999999940395355 as a `Double` and so compares below the `Double`
// threshold in `AnimatedImageFormat.delay(in:at:)`
// (`Sources/Nuke/Decoding/AnimatedImageFormat.swift:68`).
//
// Expected: [0.011, 0.011] (to float precision). WebKit, whose threshold this
// is, compares in `float` (`duration < 0.011f`) and keeps the delay.
// Actual: [0.1, 0.1] – the animation plays 9× slower than the file asks for.
//
// Target: NukeTests.
@Suite(.timeLimit(.minutes(5)))
struct DecodingMinimumDelayPrecisionBugTests {
    @Test func delayOfExactlyTheMinimumIsKept() throws {
        let data = try #require(makeAPNG(delays: [0.011, 0.011]))

        let source = try #require(AnimatedImageSource(data: data))

        #expect(source.delays.count == 2)
        for delay in source.delays {
            #expect(abs(delay - AnimatedImageSource.minimumDelay) < 0.000_001) // Actual: delay == 0.1
        }
    }

    private func makeAPNG(delays: [TimeInterval]) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, delays.count, nil) else {
            return nil
        }
        for (index, delay) in delays.enumerated() {
            let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: CGFloat(index % 2), green: 0.5, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            CGImageDestinationAddImage(destination, context.makeImage()!, [
                kCGImagePropertyPNGDictionary: [
                    kCGImagePropertyAPNGDelayTime: delay,
                    kCGImagePropertyAPNGUnclampedDelayTime: delay
                ]
            ] as CFDictionary)
        }
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
