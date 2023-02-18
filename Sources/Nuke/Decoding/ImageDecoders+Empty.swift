// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImageDecoders {
    /// A decoder that returns an empty placeholder image and attaches image
    /// data to the image container.
    public struct Empty: ImageDecoding, Sendable {
        public let isProgressive: Bool
        private let assetType: AssetType?

        public var isAsynchronous: Bool { false }

        /// Initializes the decoder.
        ///
        /// - Parameters:
        ///   - type: Image type to be associated with an image container.
        ///   `nil` by default.
        ///   - isProgressive: If `false`, returns nil for every progressive
        ///   scan. `false` by default.
        public init(assetType: AssetType? = nil, isProgressive: Bool = false) {
            self.assetType = assetType
            self.isProgressive = isProgressive
        }

        public func decode(_ data: Data) throws -> ImageContainer {
            ImageContainer(image: PlatformImage(), type: assetType, data: data, userInfo: [:])
        }

        public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
            isProgressive ? ImageContainer(image: PlatformImage(), type: assetType, data: data, userInfo: [:]) : nil
        }
    }
}
