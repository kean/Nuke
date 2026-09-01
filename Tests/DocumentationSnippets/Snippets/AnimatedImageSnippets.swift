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
