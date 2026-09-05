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
///
/// See ``AnimatedImagesDemo`` for what NukeUI does with the animated ones.
struct ImageFormatsDemo: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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

                    DemoExample("Animated GIF", caption: "state.animatedImage, played by NukeUI") {
                        LazyImage(url: DemoImages.gif) { state in
                            if let animatedImage = state.animatedImage {
                                AnimatedImage(animatedImage).resizable().scaledToFill()
                            } else if let image = state.image {
                                image.resizable().scaledToFill()
                            } else {
                                DemoPlaceholder()
                            }
                        }
                        .frame(height: 240)
                        .clipped()
                    }

                    DemoExample("Animated PNG", caption: "The default LazyImage content plays animations on its own") {
                        LazyImage(url: DemoImages.apng)
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
            .padding(.vertical, 16)
        }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Image Formats",
        "Nuke decodes with Image I/O, which covers JPEG, PNG, GIF, WebP, HEIF, and more. The decoder is chosen from the data itself, so the same request works for every format.",
        code: """
        ImageDecoderRegistry.shared.register {
            MyDecoder(context: $0)
        }
        """,
        points: [
            .init("Animated images", "The container keeps the encoded data alongside the first frame, and NukeUI plays it. The Animated Images screen shows what that costs."),
            .init("Video", "`ImageDecoders.Video` from the NukeVideo module turns an MP4 into an `AVAsset` and puts it in `ImageContainer.userInfo`."),
            .init("Custom decoders", "Register one with `ImageDecoderRegistry` to add a format. The closure sees the first chunk of the data and decides whether it can decode it."),
            .init("Decompression", "Nuke decompresses the image on a background queue so that the first draw does not stall the main thread.")
        ]
    )

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
