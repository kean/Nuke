// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG (docs vs. behavior): the GIF preview `ImageDecoders.Default`
// generates is the one preview it doesn't number.
//
// Documented:
// - `ImageDecoders.Default`: "The previews are numbered in the order they are
//   produced and the index is available in `ImageContainer/UserInfoKey/scanNumberKey`."
// - `scanNumberKey`: "The value counts the previews the decoder produced ...
//   The default decoder also attaches it to the final image, where it is the
//   total number of previews that preceded it."
//
// Actual: the GIF branch of `decodePartiallyDownloadedData(_:)`
// (`Sources/Nuke/Decoding/ImageDecoders+Default.swift:113-119`) returns the
// preview with `userInfo: [:]` and doesn't increment `numberOfScans`, so the
// preview has no `scanNumberKey`, and neither does the final image, although
// one preview preceded it. A client that tells previews apart by the key (or
// counts them from the final image) sees none for a GIF.
//
// Target: NukeTests.
@Suite(.timeLimit(.minutes(5)))
struct DecodingGIFPreviewNumberBugTests {
    @Test func gifPreviewIsNumberedLikeAnyOther() throws {
        let data = Test.data(name: "cat", extension: "gif")
        let decoder = ImageDecoders.Default()

        let preview = try #require(decoder.decodePartiallyDownloadedData(data[...60000]))
        let final = try decoder.decode(data)

        #expect(preview.userInfo[.scanNumberKey] as? Int == 1) // Actual: nil
        #expect(final.userInfo[.scanNumberKey] as? Int == 1) // Actual: nil
    }
}
