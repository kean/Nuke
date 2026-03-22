// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

#if !os(watchOS) && !os(visionOS)

import Foundation
import AVKit
import AVFoundation
import Nuke

extension ImageDecoders {
    /// The video decoder.
    ///
    /// To enable the video decoder, register it with a shared registry:
    ///
    /// ```swift
    /// ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
    /// ```
    public final class Video: ImageDecoding, @unchecked Sendable {
        private var didProducePreview = false
        private let type: AssetType

        /// Always `true` — decoding is performed asynchronously to avoid blocking the pipeline.
        public var isAsynchronous: Bool { true }

        private let lock = NSLock()

        /// Returns `nil` if the data is not a recognized video format (MP4, M4V, or MOV).
        public init?(context: ImageDecodingContext) {
            guard let type = AssetType(context.data), type.isVideo else { return nil }
            self.type = type
        }

        /// Decodes the complete video data and returns an ``ImageContainer`` with a
        /// thumbnail preview and an ``AVDataAsset`` stored in ``ImageContainer/userInfo``.
        public func decode(_ data: Data) throws -> ImageContainer {
            let image = makePreview(for: data, type: type) ?? PlatformImage()
            return ImageContainer(image: image, type: type, data: data, userInfo: [
                .videoAssetKey: AVDataAsset(data: data, type: type)
            ])
        }

        /// Returns a single thumbnail preview for the first frame of partially downloaded
        /// video data, or `nil` if the data is not yet decodable or a preview was already produced.
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
            return ImageContainer(image: preview, type: type, isPreview: true, data: data, userInfo: [
                .videoAssetKey: AVDataAsset(data: data, type: type)
            ])
        }
    }
}

extension ImageContainer.UserInfoKey {
    /// A key for a video asset (`AVAsset`).
    public static let videoAssetKey: ImageContainer.UserInfoKey = "com.github/kean/nuke/video-asset"
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

#if os(macOS)
extension NSImage {
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: .zero)
    }
}
#endif
