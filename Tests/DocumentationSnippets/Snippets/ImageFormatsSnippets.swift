// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Customization/ImageFormats/supported-image-formats.md`.

import Foundation
import Nuke

private func registerPDFDecoder() {
    ImageDecoderRegistry.shared.register(ImageDecoders.PDF.init)
}

private func loadPDFThumbnail(url: URL) async throws {
    var request = ImageRequest(url: url)
    request.thumbnail = ImageRequest.ThumbnailOptions(size: CGSize(width: 320, height: 320), contentMode: .aspectFit)
    let image = try await ImagePipeline.shared.image(for: request)
    _ = image
}

private func registerPDFDecoderWithPages() {
    ImageDecoderRegistry.shared.register { context in
        var decoder = ImageDecoders.PDF(context: context)
        decoder?.pageIndex = context.request.userInfo["pageIndex"] as? Int ?? 0
        return decoder
    }
}

private func loadPDFPage(url: URL) {
    var request = ImageRequest(url: url)
    request.userInfo["pageIndex"] = 2
    request.imageID = "\(url.absoluteString)#page=3"
    _ = request
}
