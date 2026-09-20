// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// Every screen in the demo, in the order the catalog lists them.
///
/// The catalog is built from this one list, so adding a screen is adding a
/// case. ``id`` is the name a screen is opened by from outside the app, with
/// `-demoScreen <id>`: a title can change, an id can't.
///
/// Every row pushes one of these rather than a view, so the navigation stack
/// can be put together without a tap.
enum DemoScreen: String, CaseIterable, Identifiable {
    // Essentials
    case lazyImage = "lazy-image"
    case uikitViews = "uikit-views"
    case imageProcessing = "image-processing"

    // Formats
    case imageFormats = "image-formats"
    case animatedImages = "animated-images"
    case progressiveDecoding = "progressive-decoding"
    case video = "video"

    // Performance
    case prefetching = "prefetching"
    case decompression = "decompression"

    // Integration
    case customDecoder = "custom-decoder"

    // Lab
    case priorityAndCoalescing = "priority-and-coalescing"
    case scrollStress = "scroll-stress"
    case animationLab = "animation-lab"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lazyImage: "LazyImage"
        case .uikitViews: "UIKit Views"
        case .imageProcessing: "Image Processing"
        case .imageFormats: "Image Formats"
        case .animatedImages: "Animated Images"
        case .progressiveDecoding: "Progressive Decoding"
        case .video: "Video"
        case .prefetching: "Prefetching"
        case .decompression: "Decompression"
        case .customDecoder: "Custom Decoder"
        case .priorityAndCoalescing: "Priority & Coalescing"
        case .scrollStress: "Scroll Stress"
        case .animationLab: "Animation Lab"
        }
    }

    /// The line under the title in the catalog.
    var subtitle: String {
        switch self {
        case .lazyImage: "The SwiftUI view, its options, and FetchImage"
        case .uikitViews: "loadImage(with:into:) next to LazyImageView"
        case .imageProcessing: "Processors, cache keys, and thumbnail vs resize"
        case .imageFormats: "JPEG, PNG, WebP, HEIC, GIF, and APNG, as detected"
        case .animatedImages: "GIF, APNG, WebP, and HEIC with live diagnostics"
        case .progressiveDecoding: "The scans of a progressive JPEG as they arrive"
        case .video: "A poster frame and a looping player from NukeVideo"
        case .prefetching: "ImagePrefetcher, and what it had ready in time"
        case .decompression: "Decoded off the main thread, counted in frames"
        case .customDecoder: "A toy format, picked by its first bytes"
        case .priorityAndCoalescing: "Twenty requests, six downloads, and the queue"
        case .scrollStress: "Fast scrolling with every cache disabled"
        case .animationLab: "Up to 36 animations playing from one frame pool"
        }
    }

    /// The section of the catalog that lists the screen.
    var section: CatalogSection {
        switch self {
        case .lazyImage, .uikitViews, .imageProcessing: .essentials
        case .imageFormats, .animatedImages, .progressiveDecoding, .video: .formats
        case .prefetching, .decompression: .performance
        case .customDecoder: .integration
        case .priorityAndCoalescing, .scrollStress, .animationLab: .lab
        }
    }

    /// The screen itself, without its title: ``View/demoDestinations()`` titles
    /// every screen the same way.
    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .lazyImage: LazyImageDemo()
        case .uikitViews: UIKitViewsDemo()
        case .imageProcessing: ImageProcessingDemo()
        case .imageFormats: ImageFormatsDemo()
        case .animatedImages: AnimatedImagesDemo()
        case .progressiveDecoding: ProgressiveDecodingDemo()
        case .video: VideoDemo()
        case .prefetching: PrefetchingDemo()
        case .decompression: DecompressionDemo()
        case .customDecoder: CustomDecoderDemo()
        case .priorityAndCoalescing: PriorityCoalescingDemo()
        case .scrollStress: ScrollStressDemo()
        case .animationLab: AnimationLabDemo()
        }
    }
}

extension DemoScreen {
    /// The sections of the catalog, in the order an app tends to need them
    /// rather than the order of the documentation, and the Lab last.
    enum CatalogSection: CaseIterable {
        case essentials
        case formats
        case performance
        case integration
        /// Stress rigs for working on Nuke, where the rest of the catalog is
        /// for adopting it. A Lab screen may cripple the pipeline to make a
        /// point – disable its caches, push its budgets past sensible values –
        /// and it reports numbers rather than explaining an API. It ends with
        /// the switch of the pipeline HUD.
        case lab

        var title: String {
            switch self {
            case .essentials: "Essentials"
            case .formats: "Formats"
            case .performance: "Performance"
            case .integration: "Integration"
            case .lab: "Lab"
            }
        }

        var footer: String {
            switch self {
            case .essentials: "What most apps need: LazyImage for SwiftUI, the image views for UIKit, and the processors that fit an image to either."
            case .formats: "What the pipeline decodes: still images, animations, the scans of a progressive JPEG as they arrive, and, with NukeVideo, video."
            case .performance: "How to have an image ready before it is needed, and what decoding off the main thread saves."
            case .integration: "Where an app plugs into the pipeline with a decoder for a format of its own."
            case .lab: "Stress rigs for whoever works on Nuke. Caches are turned off where they would hide the work, and the screens report numbers rather than explain them – the sections above do that. The pipeline HUD stands over every screen, and its info button opens the details of the pipeline it shows."
            }
        }

        var screens: [DemoScreen] {
            DemoScreen.allCases.filter { $0.section == self }
        }
    }
}

extension View {
    /// Resolves the ``DemoScreen`` values pushed onto the navigation stack
    /// this view is in. The catalog registers it once, at the root, for the
    /// whole stack.
    func demoDestinations() -> some View {
        navigationDestination(for: DemoScreen.self) { screen in
            screen.destination
                .navigationTitle(screen.title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
