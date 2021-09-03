// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).


#if !os(watchOS)

import Foundation
import AVKit

extension ImageType {
    public static let mp4: ImageType = "public.mp4"
}

extension ImageDecoders {
    public final class Video: ImageDecoding, ImageDecoderRegistering {
        private var didProducePreview = false

        static func isVideo(_ data: Data) -> Bool {
            match(data, offset: 4, [0x66, 0x74, 0x79, 0x70])
        }

        public var isAsynchronous: Bool {
            false
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
    #if os(macOS)
    return PlatformImage(cgImage: cgImage, size: .zero)
    #else
    return PlatformImage(cgImage: cgImage)
    #endif
}

// TODO: extened support for other image formats
// ftypisom - ISO Base Media file (MPEG-4) v1
// There are a bunch of other ways to create MP4
// https://www.garykessler.net/library/file_sigs.html
private func match(_ data: Data, offset: Int = 0, _ numbers: [UInt8]) -> Bool {
    guard data.count >= numbers.count + offset else { return false }
    return !zip(numbers.indices, numbers).contains { (index, number) in
        data[index + offset] != number
    }
}

#endif
