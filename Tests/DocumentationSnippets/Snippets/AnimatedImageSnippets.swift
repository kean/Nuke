// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/NukeUI.docc/AnimatedImages.md`.
//
// This target exists only to make the hand-written samples in the articles
// compile. If a snippet here stops building, the article is out of date.

import NukeUI
import SwiftUI
import UIKit

// MARK: - Overview

private struct DefaultContentView: View {
    var body: some View {
        LazyImage(url: URL(string: "https://example.com/cat.gif"))
    }
}

// MARK: - SwiftUI

private struct AnimatedContentView: View {
    let url: URL

    var body: some View {
        LazyImage(url: url) { state in
            if let animatedImage = state.animatedImage {
                AnimatedImage(animatedImage).resizable().scaledToFill()
            } else if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
    }
}

// MARK: - UIKit and AppKit

@MainActor
private func makeLazyImageView(url: URL) -> LazyImageView {
    let imageView = LazyImageView()
    imageView.url = url
    return imageView
}

@MainActor
private func makeAnimatedImageView(url: URL) -> AnimatedImageView {
    let imageView = AnimatedImageView()
    imageView.contentMode = .scaleAspectFill
    NukeUI.loadImage(with: url, into: imageView)
    return imageView
}

// MARK: - Memory

@MainActor
private func setPoolCostLimit() {
    AnimatedImageFramePool.shared.costLimit = 32 * 1_048_576
}

@MainActor
private func downsample(_ imageView: AnimatedImageView) {
    var options = AnimatedImagePlayer.Options()
    options.maxPixelSize = 240
    imageView.playerOptions = options
}

// MARK: - Controlling Playback

@MainActor
private func makePlayer(source: AnimatedImageSource) -> AnimatedImagePlayer {
    let player = AnimatedImagePlayer(source: source)
    player.play()
    return player
}

@MainActor
private func attach(_ player: AnimatedImagePlayer, to imageView: AnimatedImageView) {
    imageView.player = player
}

private struct PlayerContentView: View {
    let player: AnimatedImagePlayer

    var body: some View {
        AnimatedImage(player: player)
    }
}

// MARK: - Custom Frames

@MainActor
private func transformFrames(_ imageView: AnimatedImageView) {
    var options = AnimatedImagePlayer.Options()
    options.frameTransform = AnimatedImageFrameTransform(identifier: "grayscale") {
        $0.copy(colorSpace: CGColorSpaceCreateDeviceGray())
    }
    imageView.playerOptions = options
}

// MARK: - Custom Formats

private func registerAnimatedFormatDecoder() {
    ImageDecoderRegistry.shared.register(WebPDecoder.init(context:))
}

/// Stands in for the decoder the article's snippet registers.
private struct WebPDecoder: ImageDecoding {
    init?(context: ImageDecodingContext) {
        guard context.isCompleted, AssetType(context.data) == .webp else {
            return nil // Not this format, or not all of it yet
        }
    }

    func decode(_ data: Data) throws -> ImageContainer {
        let webp = try WebPImage(data: data)
        var container = ImageContainer(image: webp.makeFirstFrame())
        container.data = data
        container.animation = AnimatedImageSource(
            data: data,
            delays: webp.delays,
            loopCount: webp.loopCount,
            size: webp.size,
            makeFrameDecoder: { WebPFrameDecoder(webp, maxPixelSize: $0) }
        )
        return container
    }
}

/// Stands in for the frame decoder the article's snippet hands over.
private actor WebPFrameDecoder: AnimatedImageFrameDecoding {
    init(_ image: WebPImage, maxPixelSize: CGFloat?) {}

    func decode(at index: Int) -> CGImage? { nil }
}

/// Stands in for a codec the system doesn't have.
private struct WebPImage: Sendable {
    let delays: [TimeInterval] = []
    let loopCount = 0
    let size: CGSize = .zero

    init(data: Data) throws {}

    func makeFirstFrame() -> PlatformImage { PlatformImage() }
}
