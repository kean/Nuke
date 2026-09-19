// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: since 9b1973f8 ("Read the brand of an image sequence past the
// major one"), `AssetType.init(_ data:)` walks every compatible brand in the
// `ftyp` box and returns the first one it knows
// (`Sources/Nuke/Decoding/AssetType.swift:174-181`). Real MPEG-4 audio and
// Canon CR3 raw files list the generic `mp42`/`isom` brands among their
// compatible brands, so they now sniff as `.mp4`.
//
// Expected (documented):
// - the doc comment on `_makeISOBaseMedia(_:)` says it returns `nil` "as for
//   bare HEIF (`mif1`) or MPEG-4 audio (`M4A `)";
// - "Supported Formats" says camera RAW files that aren't TIFF containers,
//   "such as Canon's ISO-base-media CR3, sniff as `nil`".
//
// Actual: both sniff as `.mp4`. `AssetType.isVideo` (NukeVideo) is then
// `true`, so a registered `ImageDecoders.Video` claims an `.m4a` or a `.cr3`
// ahead of `ImageDecoders.Default` and returns an empty placeholder image
// instead of letting Image I/O decode the CR3.
//
// The existing `AssetTypeTests.detectUnsupportedISOBaseMediaBrands` only covers
// a bare `M4A ` major brand with no compatible brands, which no encoder writes.
//
// Target: NukeTests.
@Suite(.timeLimit(.minutes(5)))
struct DecodingISOBaseMediaCompatibleBrandBugTests {
    @Test func mpeg4AudioWrittenByAppleToolsSniffsAsNothing() {
        // The `ftyp` box `afconvert -f m4af -d aac` writes: major brand `M4A `,
        // minor version 0, compatible brands `M4A `, `mp42`, `isom`, and a
        // zero brand.
        let data = Data([0x00, 0x00, 0x00, 0x1C]) + Data("ftypM4A ".utf8) + Data(count: 4)
            + Data("M4A mp42isom".utf8) + Data(count: 4)
            + Data([0x00, 0x00, 0x04, 0x6E]) + Data("moov".utf8)

        #expect(AssetType(data) == nil) // Actual: .mp4
    }

    @Test func canonRawSniffsAsNothing() {
        // The `ftyp` box of a CR3: major brand `crx `, minor version 1,
        // compatible brands `crx ` and `isom`.
        let data = Data([0x00, 0x00, 0x00, 0x18]) + Data("ftypcrx ".utf8) + Data([0x00, 0x00, 0x00, 0x01])
            + Data("crx isom".utf8)

        #expect(AssetType(data) == nil) // Actual: .mp4
    }
}
