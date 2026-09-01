// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// The demo catalog. The sections mirror the structure of the Nuke
/// documentation: Essentials, Customization, and Performance.
struct DemoMenu: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    DemoLink("Image Pipeline", "Async/await, progress, cancellation") {
                        ImagePipelineDemo()
                    }
                    DemoLink("LazyImage", "The SwiftUI view and all of its options") {
                        LazyImageDemo()
                    }
                    DemoLink("UIImageView", "loadImage(with:into:) and cell reuse") {
                        ImageViewDemo()
                    }
                    DemoLink("LazyImageView", "The UIKit and AppKit view") {
                        LazyImageViewDemo()
                    }
                } header: {
                    Text("Essentials")
                } footer: {
                    Text("The APIs you need for most apps: ImagePipeline, LazyImage, and the image view extensions.")
                }

                Section {
                    DemoLink("Image Processing", "Resize, blur, circle, and custom processors") {
                        ImageProcessingDemo()
                    }
                    DemoLink("Image Formats", "JPEG, PNG, GIF, WebP, and MP4") {
                        ImageFormatsDemo()
                    }
                    DemoLink("Animated Images", "GIF, APNG, WebP, and HEIC with live diagnostics") {
                        AnimatedImagesDemo()
                    }
                    DemoLink("Frame Pool", "A wall of animations sharing one memory budget") {
                        AnimatedImageFramePoolDemo()
                    }
                    DemoLink("Progressive JPEG", "Progressive decoding side by side with baseline") {
                        ProgressiveDecodingDemo()
                    }
                    DemoLink("Pipeline Delegate", "Intercept requests and observe pipeline events") {
                        PipelineDelegateDemo()
                    }
                } header: {
                    Text("Customization")
                } footer: {
                    Text("Every stage of the pipeline is replaceable: data loading, decoding, processing, and caching.")
                }

                Section {
                    DemoLink("Prefetching", "ImagePrefetcher in UIKit and SwiftUI") {
                        PrefetchingDemo()
                    }
                    DemoLink("Caching", "Memory, HTTP, and aggressive disk cache") {
                        CachingDemo()
                    }
                    DemoLink("Stress Test", "Rate limiting and coalescing under pressure") {
                        StressTestDemo()
                    }
                } header: {
                    Text("Performance")
                } footer: {
                    Text("Nuke Demo · Documentation: kean-docs.github.io/nuke")
                }
            }
            .navigationTitle("Nuke")
        }
    }
}

/// A menu row that pushes a demo screen.
private struct DemoLink<Destination: View>: View {
    private let title: String
    private let subtitle: String
    private let destination: () -> Destination

    init(_ title: String, _ subtitle: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.title = title
        self.subtitle = subtitle
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }
}

#Preview {
    DemoMenu()
}
