// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import ImageIO
@testable import Nuke

// SUSPECTED BUG: a thumbnail request gets full-size progressive previews.
//
// `ImageRequest.thumbnail` is documented as "When set, the pipeline generates
// a thumbnail instead of a full image. Thumbnail creation is generally
// significantly more efficient, especially in terms of memory usage". The
// default decoder honors it in `decode(_:)` only:
// `decodePartiallyDownloadedData(_:)`
// (`Sources/Nuke/Decoding/ImageDecoders+Default.swift:100-160`) never looks at
// `thumbnail`, so with `.incremental` – the default policy for a progressive
// JPEG, used whenever `isProgressiveDecodingEnabled` is on – every preview is
// decoded at the full size of the image with `CGImageSourceCreateImageAtIndex`.
//
// Expected: the previews of a thumbnail request are no larger than the
// thumbnail the request asks for (or there are none).
// Actual: for `progressive.jpeg` (450×300) and `maxPixelSize: 64`, the preview
// is 450×300 while the final image is 64×43. For a 12 MP camera JPEG that is
// ~48 MB per preview bitmap, produced for a request that asked for a 64 px
// image specifically to save memory, and the preview can land in the memory
// cache under the thumbnail's key.
//
// Target: NukeTests. Fails on macOS and iOS.
@Suite(.timeLimit(.minutes(5)))
struct DecodingThumbnailRequestPreviewBugTests {
    @Test func previewOfAThumbnailRequestIsNoLargerThanTheThumbnail() throws {
        let data = Test.data(name: "progressive", extension: "jpeg")
        var request = ImageRequest(url: URL(string: "https://example.com/a.jpg"))
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 64)
        let context = ImageDecodingContext(request: request, data: data, isCompleted: false, previewPolicy: .default(for: data))
        #expect(context.previewPolicy == .incremental)
        let decoder = try #require(ImageDecoders.Default(context: context))

        let preview = try #require(decoder.decodePartiallyDownloadedData(data[0..<20000]))
        let final = try decoder.decode(data)

        #expect(final.image.sizeInPixels == CGSize(width: 64, height: 43))
        // Actual: 450×300
        #expect(max(preview.image.sizeInPixels.width, preview.image.sizeInPixels.height) <= 64)
    }
}
