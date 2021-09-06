// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).


#if !os(watchOS)

import Foundation
import AVKit

extension ImageDecoders {
    public final class Video: ImageDecoding, ImageDecoderRegistering {
        private var didProducePreview = false

        static func isVideo(_ data: Data) -> Bool {
            ImageType(data) == .mp4
        }

        public var isAsynchronous: Bool {
            true
        }

        public init?(data: Data, context: ImageDecodingContext) {
            guard Video.isVideo(data) else { return nil }
        }

        public init?(partiallyDownloadedData data: Data, context: ImageDecodingContext) {
            guard Video.isVideo(data) else { return nil }
        }

        public func decode(_ data: Data) -> ImageContainer? {
            ImageContainer(image: PlatformImage(), type: .mp4, data: data)
        }

        public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
            guard !didProducePreview else {
                return nil // We only need one preview
            }
            guard let preview = makePreview(for: data) else {
                return nil
            }
            didProducePreview = true
            return ImageContainer(image: preview, type: .mp4, isPreview: true, data: data)
        }
    }
}

private func makePreview(for data: Data) -> PlatformImage? {
    let asset = AVDataAsset(data: data)
    let generator = AVAssetImageGenerator(asset: asset)
    guard let cgImage = try? generator.copyCGImage(at: CMTime(value: 0, timescale: 1), actualTime: nil) else {
        return nil
    }
    return PlatformImage(cgImage: cgImage)
}

#endif
