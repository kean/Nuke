// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG (performance, hostile input): `AssetType._brands(in:)`
// (`Sources/Nuke/Decoding/AssetType.swift:186-196`) reads a compatible brand
// every 4 bytes up to `min(declared box size, data.count)`, allocating a
// `String` for each, and `_makeISOBaseMedia(_:)` only stops at a brand it
// knows. A file with `ftyp` at offset 4, a declared size of 0xFFFFFFFF, and no
// known brand makes every `AssetType(data)` walk the entire file: 2.6 s for
// 32 MB in a Debug build on macOS, 4.6 s on the iOS simulator (measured under
// load), where a header sniff should take microseconds.
//
// The sniff runs on the pipeline's actor: `ImageDecoders.Default` is
// synchronous unless a thumbnail is requested (`isAsynchronous` is
// `thumbnail != nil`) and calls `AssetType(data)` in `decode(_:)`;
// `PreviewPolicy.default(for:)` and `ImageDecoders.Video.init?(context:)` sniff
// there too, and with progressive decoding every downloaded chunk is sniffed
// again. One such image stalls every image load of the pipeline for seconds,
// every time it is loaded.
//
// Expected: the sniff reads a bounded header – a real `ftyp` box is a few
// dozen bytes – so its cost doesn't depend on the size of the file.
// Actual: O(file size) with a `String` allocation per 4 bytes.
//
// The first test is a timing test with a >25× margin over a Debug build (the
// work is 2.6–4.6 s here; a header sniff is microseconds). The second shows the
// same thing deterministically: a brand 1 MB into the data is still read.
//
// Target: NukeTests.
@Suite(.timeLimit(.minutes(5)))
struct DecodingFileTypeBoxWalkBugTests {
    @Test func sniffingIsBoundedByTheHeaderNotTheFile() {
        var data = Data([0xFF, 0xFF, 0xFF, 0xFF]) + Data("ftyp".utf8) + Data("zzzz".utf8) + Data(count: 4)
        data += Data(repeating: 0x41, count: 32_000_000)

        let clock = ContinuousClock()
        var type: AssetType?
        let elapsed = clock.measure {
            type = AssetType(data)
        }

        #expect(type == nil)
        #expect(elapsed < .milliseconds(100)) // Actual: seconds
    }

    @Test func brandFarPastAnyRealFileTypeBoxIsNotRead() {
        var data = Data([0xFF, 0xFF, 0xFF, 0xFF]) + Data("ftyp".utf8) + Data("zzzz".utf8) + Data(count: 4)
        data += Data(repeating: 0x41, count: 1_000_000)
        data += Data("heic".utf8)

        #expect(AssetType(data) == nil) // Actual: .heic, read 1 MB into the file
    }
}
