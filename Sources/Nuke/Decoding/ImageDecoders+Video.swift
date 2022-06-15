// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

#if !os(watchOS)

import Foundation
import AVKit

extension ImageDecoders {
    public final class Video: ImageDecoding, @unchecked Sendable {
        private var didProducePreview = false
        private let type: AssetType
        public var isAsynchronous: Bool { true }

        private let lock = NSLock()

        public init?(context: ImageDecodingContext) {
            guard let type = AssetType(context.data), type.isVideo else { return nil }
            self.type = type
        }

        public func decode(_ data: Data) throws -> ImageContainer {
            ImageContainer(image: PlatformImage(), type: type, data: data)
        }

        public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
            lock.lock()
            defer { lock.unlock() }

            guard let type = AssetType(data), type.isVideo else { return nil }
            guard !didProducePreview else {
                return nil // We only need one preview
            }
            guard let preview = makePreview(for: data, type: type) else {
                return nil
            }
            didProducePreview = true
            return ImageContainer(image: preview, type: type, isPreview: true, data: data)
        }
    }
}

private func makePreview(for data: Data, type: AssetType) -> PlatformImage? {
    let asset = AVDataAsset(data: data, type: type)
    let generator = AVAssetImageGenerator(asset: asset)
    guard let cgImage = try? generator.copyCGImage(at: CMTime(value: 0, timescale: 1), actualTime: nil) else {
        return nil
    }
    return PlatformImage(cgImage: cgImage)
}

#endif
