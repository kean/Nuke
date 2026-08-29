// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import AVFoundation
import NukeUI
import NukeVideo
import SwiftUI

/// Demonstrates the image formats that Nuke supports out of the box and the
/// video decoder from the NukeVideo module.
///
/// The decoders are selected by ``ImageDecoderRegistry`` based on the image
/// data, so a single request works for any of these formats.
struct ImageFormatsDemo: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DemoIntro("Nuke uses ImageIO, which supports JPEG, PNG, GIF, WebP, HEIF, and more. Animated images and videos are decoded into an `ImageContainer` that carries the original data alongside the first frame, so you can hand it to any view that can play it.")

                Group {
                    DemoExample("JPEG", caption: "Decoded and decompressed in the background") {
                        image(for: DemoImages.landscape)
                    }

                    DemoExample("PNG", caption: "Transparency is preserved") {
                        image(for: DemoImages.png)
                    }

                    DemoExample("WebP", caption: "Supported natively since iOS 14") {
                        image(for: DemoImages.webp)
                    }

                    DemoExample("Animated GIF", caption: "container.type == .gif, rendered from container.data") {
                        LazyImage(url: DemoImages.gif) { state in
                            if let container = state.imageContainer, container.type == .gif, let data = container.data {
                                AnimatedImage(data: data)
                            } else if let image = state.image {
                                image.resizable().scaledToFill()
                            } else {
                                DemoPlaceholder()
                            }
                        }
                        .frame(height: 240)
                        .clipped()
                    }

                    DemoExample("Video", caption: "ImageDecoders.Video from the NukeVideo module") {
                        LazyImage(url: DemoImages.video) { state in
                            if let asset = state.imageContainer?.userInfo[.videoAssetKey] as? AVAsset {
                                VideoPlayerRepresentable(asset: asset)
                            } else {
                                DemoPlaceholder()
                            }
                        }
                        .frame(height: 240)
                        .clipped()
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 32)
        }
    }

    private func image(for url: URL) -> some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFit()
            } else {
                DemoPlaceholder()
            }
        }
        .frame(height: 200)
    }
}

/// Plays a video decoded by ``ImageDecoders/Video`` using the player view from
/// the NukeVideo module.
private struct VideoPlayerRepresentable: UIViewRepresentable {
    let asset: AVAsset

    func makeUIView(context: Context) -> VideoPlayerView {
        let view = VideoPlayerView()
        view.asset = asset
        view.play()
        return view
    }

    func updateUIView(_ view: VideoPlayerView, context: Context) {
        // Do nothing
    }
}
