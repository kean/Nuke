// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// Every screen in the demo, in the order the menus list them.
///
/// The catalog and the Lab menu are both built from this one list, so adding a
/// screen is adding a case. ``id`` is the name a screen is opened by from
/// outside the app, with `-demoScreen <id>`: a title can change, an id can't.
enum DemoScreen: String, CaseIterable, Identifiable {
    // Essentials
    case imagePipeline = "image-pipeline"
    case lazyImage = "lazy-image"
    case uikitViews = "uikit-views"

    // Processing & Formats
    case imageProcessing = "image-processing"
    case imageFormats = "image-formats"
    case progressiveDecoding = "progressive-decoding"

    // Caching & Performance
    case caching = "caching"
    case prefetching = "prefetching"

    // Animated Images
    case animatedImages = "animated-images"

    // Integration
    case pipelineDelegate = "pipeline-delegate"

    // Lab
    case scrollStress = "scroll-stress"
    case animationMemory = "animation-memory"
    case automation = "automation"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .imagePipeline: "Image Pipeline"
        case .lazyImage: "LazyImage"
        case .uikitViews: "UIKit Views"
        case .imageProcessing: "Image Processing"
        case .imageFormats: "Image Formats"
        case .progressiveDecoding: "Progressive Decoding"
        case .caching: "Caching"
        case .prefetching: "Prefetching"
        case .animatedImages: "Animated Images"
        case .pipelineDelegate: "Pipeline Delegate"
        case .scrollStress: "Scroll Stress"
        case .animationMemory: "Animation Memory"
        case .automation: "Automation"
        }
    }

    /// The line under the title in the menu.
    var subtitle: String {
        switch self {
        case .imagePipeline: "Async/await, progress, cancellation"
        case .lazyImage: "The SwiftUI view and all of its options"
        case .uikitViews: "loadImage(with:into:) next to LazyImageView"
        case .imageProcessing: "Resize, blur, circle, and custom processors"
        case .imageFormats: "JPEG, PNG, GIF, WebP, and MP4"
        case .progressiveDecoding: "The scans of a progressive JPEG as they arrive"
        case .caching: "Memory, HTTP, and aggressive disk cache"
        case .prefetching: "ImagePrefetcher in UIKit and SwiftUI"
        case .animatedImages: "GIF, APNG, WebP, and HEIC with live diagnostics"
        case .pipelineDelegate: "Intercept requests and observe pipeline events"
        case .scrollStress: "Fast scrolling with every cache disabled"
        case .animationMemory: "A wall of animations sharing one memory budget"
        case .automation: "Launch arguments and the id of every screen"
        }
    }

    var placement: Placement {
        switch self {
        case .imagePipeline, .lazyImage, .uikitViews: .catalog(.essentials)
        case .imageProcessing, .imageFormats, .progressiveDecoding: .catalog(.processingAndFormats)
        case .caching, .prefetching: .catalog(.cachingAndPerformance)
        case .animatedImages: .catalog(.animatedImages)
        case .pipelineDelegate: .catalog(.integration)
        case .scrollStress: .lab(.stress)
        case .animationMemory: .lab(.animation)
        case .automation: .lab(.rig)
        }
    }

    /// The screen itself, without its title: ``View/demoDestinations()`` titles
    /// every screen the same way.
    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .imagePipeline: ImagePipelineDemo()
        case .lazyImage: LazyImageDemo()
        case .uikitViews: UIKitViewsDemo()
        case .imageProcessing: ImageProcessingDemo()
        case .imageFormats: ImageFormatsDemo()
        case .progressiveDecoding: ProgressiveDecodingDemo()
        case .caching: CachingDemo()
        case .prefetching: PrefetchingDemo()
        case .animatedImages: AnimatedImagesDemo()
        case .pipelineDelegate: PipelineDelegateDemo()
        case .scrollStress: ScrollStressDemo()
        case .animationMemory: AnimationMemoryDemo()
        case .automation: AutomationDemo()
        }
    }
}

extension DemoScreen {
    /// Where a screen is listed: a section of the catalog, or a group in the Lab.
    enum Placement: Hashable {
        case catalog(CatalogSection)
        case lab(LabGroup)
    }

    /// The sections of the catalog, in the order an app tends to need them
    /// rather than the order of the documentation.
    enum CatalogSection: CaseIterable {
        case essentials
        case requests
        case processingAndFormats
        case cachingAndPerformance
        case animatedImages
        case integration

        var title: String {
            switch self {
            case .essentials: "Essentials"
            case .requests: "Requests"
            case .processingAndFormats: "Processing & Formats"
            case .cachingAndPerformance: "Caching & Performance"
            case .animatedImages: "Animated Images"
            case .integration: "Integration"
            }
        }

        var footer: String {
            switch self {
            case .essentials: "The APIs you need for most apps: ImagePipeline, LazyImage, and the image views for UIKit."
            case .requests: "What a request can ask of the pipeline, and what the pipeline does when many ask at once."
            case .processingAndFormats: "Decoders turn data into images, and processors turn those into the ones you display."
            case .cachingAndPerformance: "Where an image comes from the second time it's needed, and how to have it ready before the first."
            case .animatedImages: "Frames decoded as they play, within a memory budget you can watch."
            case .integration: "Where an app plugs into the pipeline: changing its requests and observing its events."
            }
        }

        /// Empty for a section that has no screens yet, which the catalog leaves out.
        var screens: [DemoScreen] {
            DemoScreen.allCases.filter { $0.placement == .catalog(self) }
        }
    }

    /// The groups of the Lab menu.
    enum LabGroup: CaseIterable {
        case instruments
        case stress
        case animation
        case fixtures
        case rig

        var title: String {
            switch self {
            case .instruments: "Instruments"
            case .stress: "Stress"
            case .animation: "Animation"
            case .fixtures: "Fixtures"
            case .rig: "Rig"
            }
        }

        /// Empty for a group that has no screens yet, which the Lab leaves out.
        var screens: [DemoScreen] {
            DemoScreen.allCases.filter { $0.placement == .lab(self) }
        }
    }
}

/// A stop on the demo's navigation stack: the Lab menu, or a screen.
///
/// Every row in the menus pushes one of these rather than a view, so a stack
/// can be put together without a tap – see ``stack``.
enum DemoRoute: Hashable {
    case lab
    case screen(DemoScreen)

    /// The name the route is opened by from outside the app: the screen's
    /// ``DemoScreen/id``, or `lab` for the Lab menu, which no screen can take.
    var id: String {
        switch self {
        case .lab: "lab"
        case .screen(let screen): screen.id
        }
    }

    init?(id: String) {
        if id == DemoRoute.lab.id {
            self = .lab
        } else if let screen = DemoScreen(rawValue: id) {
            self = .screen(screen)
        } else {
            return nil
        }
    }

    /// The navigation stack that shows the route, with the menus it is reached
    /// through beneath it, so that Back goes where it would after a tap: a
    /// catalog screen is `[.screen(screen)]`, a Lab screen
    /// `[.lab, .screen(screen)]`.
    var stack: [DemoRoute] {
        switch self {
        case .lab:
            [.lab]
        case .screen(let screen):
            switch screen.placement {
            case .catalog: [self]
            case .lab: [.lab, self]
            }
        }
    }
}

extension View {
    /// Resolves the ``DemoRoute`` values pushed onto the navigation stack this
    /// view is in. The catalog registers it once, at the root, for the whole
    /// stack, the Lab included.
    func demoDestinations() -> some View {
        navigationDestination(for: DemoRoute.self) { route in
            switch route {
            case .lab:
                LabMenu()
            case .screen(let screen):
                screen.destination
                    .navigationTitle(screen.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}
