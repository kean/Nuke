// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

enum ImageDecompression {

    static func decompress(image: PlatformImage, isUsingPrepareForDisplay: Bool = false) -> PlatformImage {
        image.decompressed(isUsingPrepareForDisplay: isUsingPrepareForDisplay) ?? image
    }

    // MARK: Managing Decompression State

    static var isDecompressionNeededAK = "ImageDecompressor.isDecompressionNeeded.AssociatedKey"

    static func setDecompressionNeeded(_ isDecompressionNeeded: Bool, for image: PlatformImage) {
        objc_setAssociatedObject(image, &isDecompressionNeededAK, isDecompressionNeeded, .OBJC_ASSOCIATION_RETAIN)
    }

    static func isDecompressionNeeded(for image: PlatformImage) -> Bool? {
        objc_getAssociatedObject(image, &isDecompressionNeededAK) as? Bool
    }
}
