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

    // Processing & Formats
    case imageProcessing = "image-processing"
    case imageFormats = "image-formats"
    case animatedImages = "animated-images"
    case progressiveDecoding = "progressive-decoding"
    case customDecoder = "custom-decoder"

    // Caching & Performance
    case caching = "caching"
    case prefetching = "prefetching"
    case decompression = "decompression"

    // Integration
    case customDataLoader = "custom-data-loader"
    case video = "video"

    // Lab
    case priorityAndCoalescing = "priority-and-coalescing"
    case pipelineHUD = "pipeline-hud"
    case concurrencyInspector = "concurrency-inspector"
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
        case .customDecoder: "Custom Decoder"
        case .caching: "Caching"
        case .prefetching: "Prefetching"
        case .decompression: "Decompression"
        case .customDataLoader: "Custom Data Loader"
        case .video: "Video"
        case .priorityAndCoalescing: "Priority & Coalescing"
        case .pipelineHUD: "Pipeline HUD"
        case .concurrencyInspector: "Concurrency Inspector"
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
        case .customDecoder: "A toy format, picked by its first bytes"
        case .caching: "Memory and disk caches, and what each policy keeps"
        case .prefetching: "ImagePrefetcher, and what it had ready in time"
        case .decompression: "Decoded off the main thread, counted in frames"
        case .customDataLoader: "Throttled, bundled, and failing loaders, call by call"
        case .video: "A poster frame and a looping player from NukeVideo"
        case .priorityAndCoalescing: "Twenty requests, six downloads, and the queue"
        case .pipelineHUD: "Each pipeline's figures, over any screen"
        case .concurrencyInspector: "A burst's tasks and the five queues"
        case .scrollStress: "Fast scrolling with every cache disabled"
        case .animationLab: "Up to 36 animations playing from one frame pool"
        }
    }

    var section: CatalogSection {
        switch self {
        case .lazyImage, .uikitViews: .essentials
        case .imageProcessing, .imageFormats, .animatedImages, .progressiveDecoding, .customDecoder: .processingAndFormats
        case .caching, .prefetching, .decompression: .cachingAndPerformance
        case .customDataLoader, .video: .integration
        case .priorityAndCoalescing, .pipelineHUD, .concurrencyInspector, .scrollStress, .animationLab: .lab
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
        case .customDecoder: CustomDecoderDemo()
        case .caching: CachingDemo()
        case .prefetching: PrefetchingDemo()
        case .decompression: DecompressionDemo()
        case .customDataLoader: CustomDataLoaderDemo()
        case .video: VideoDemo()
        case .priorityAndCoalescing: PriorityCoalescingDemo()
        case .pipelineHUD: PipelineHUDDemo()
        case .concurrencyInspector: ConcurrencyInspectorDemo()
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
        case processingAndFormats
        case cachingAndPerformance
        case integration
        /// Instruments and stress rigs for working on Nuke, where the rest of
        /// the catalog is for adopting it. A Lab screen may cripple the
        /// pipeline to make a point – disable its caches, push its budgets
        /// past sensible values – and it reports numbers rather than
        /// explaining an API.
        case lab

        var title: String {
            switch self {
            case .essentials: "Essentials"
            case .processingAndFormats: "Processing & Formats"
            case .cachingAndPerformance: "Caching & Performance"
            case .integration: "Integration"
            case .lab: "Lab"
            }
        }

        var footer: String {
            switch self {
            case .essentials: "The views you need for most apps: LazyImage for SwiftUI, and the image views for UIKit."
            case .processingAndFormats: "Decoders turn data into images, and processors turn those into the ones you display."
            case .cachingAndPerformance: "Where an image comes from the second time it's needed, how to have it ready before the first, and what decoding off the main thread saves."
            case .integration: "Where an app plugs into the pipeline: a data loader of its own, and a decoder for video."
            case .lab: "Instruments and stress rigs for whoever works on Nuke. Caches are turned off where they would hide the work, and the screens report numbers rather than explain them – the sections above do that."
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
    /// whole stack. Every screen leaves room for the pipeline HUD.
    func demoDestinations() -> some View {
        navigationDestination(for: DemoScreen.self) { screen in
            screen.destination
                .navigationTitle(screen.title)
                .navigationBarTitleDisplayMode(.inline)
                .demoHUDRoom()
        }
    }
}
