// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI

/// Demonstrates ``LazyImage`` – the SwiftUI view for displaying remote images.
///
/// ```swift
/// LazyImage(url: url)
/// ```
struct LazyImageDemo: View {
    @State private var reloadToken = UUID()
    @State private var lastResult: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Group {
                    DemoExample("Default", caption: "LazyImage(url:) displays the image at its natural size") {
                        LazyImage(url: DemoImages.photos[0])
                            .frame(maxWidth: .infinity)
                            .clipped()
                    }

                    DemoExample("Custom Content", caption: "A view for each of the loading states") {
                        LazyImage(url: DemoImages.photos[1]) { state in
                            if let image = state.image {
                                image.resizable().scaledToFill()
                            } else if state.error != nil {
                                DemoFailureView()
                            } else {
                                DemoPlaceholder()
                            }
                        }
                        .frame(height: 180)
                        .clipped()
                    }

                    DemoExample("Transition", caption: "A transaction animates the state changes") {
                        LazyImage(url: DemoImages.photos[2], transaction: Transaction(animation: .easeInOut(duration: 0.4))) { state in
                            if let image = state.image {
                                image.resizable().scaledToFill()
                            } else {
                                Color(.secondarySystemBackground)
                            }
                        }
                        .frame(height: 180)
                        .clipped()
                    }

                    DemoExample("Processors", caption: ".processors([.resize(width: 48), .circle()])") {
                        HStack(spacing: 12) {
                            ForEach(DemoImages.avatars, id: \.self) { url in
                                LazyImage(url: url) { state in
                                    if let image = state.image {
                                        image.resizable().scaledToFit()
                                    } else {
                                        Circle().fill(Color(.secondarySystemBackground))
                                    }
                                }
                                .processors([.resize(width: 48), .circle()])
                                .frame(width: 48, height: 48)
                            }
                        }
                    }

                    DemoExample("Priority and Completion", caption: ".priority(.high).onCompletion { ... }") {
                        LazyImage(url: DemoImages.photos[3]) { state in
                            if let image = state.image {
                                image.resizable().scaledToFill()
                            } else {
                                DemoPlaceholder()
                            }
                        }
                        .priority(.high)
                        .onCompletion { result in
                            switch result {
                            case .success(let response):
                                lastResult = response.cacheType == nil ? "Loaded from the network" : "Loaded from the cache"
                            case .failure(let error):
                                lastResult = error.description
                            }
                        }
                        .frame(height: 180)
                        .clipped()

                        if let lastResult {
                            DemoBadge(lastResult)
                        }
                    }

                    DemoExample("Failure", caption: "A URL that always fails") {
                        LazyImage(url: DemoImages.failing) { state in
                            if let image = state.image {
                                image.resizable().scaledToFill()
                            } else if state.error != nil {
                                DemoFailureView()
                            } else {
                                DemoPlaceholder()
                            }
                        }
                        .frame(height: 120)
                        .clipped()
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
        .id(reloadToken)
        .toolbar {
            Button {
                ImagePipeline.shared.cache.removeAll()
                lastResult = nil
                reloadToken = UUID()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "LazyImage",
        "`LazyImage` is the SwiftUI view for remote images. It is designed to look like the native `AsyncImage`, but it loads through Nuke, so caching, prefetching, coalescing, progressive decoding, and priorities all come for free.",
        code: """
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                Color.secondary
            }
        }
        """,
        points: [
            .init("States", "The closure receives a `LazyImageState` with the image, the error, and the download progress. Without a closure the view displays the image and nothing else."),
            .init("Transitions", "Pass a `Transaction` to animate the change from the placeholder to the image."),
            .init("Processors", "`.processors(_:)` attaches them to the request. The processed image is cached, so the work is done once."),
            .init("Priority", "`.priority(.high)` raises the priority of the request. When the view disappears the request is cancelled, or, with `.onDisappear(.lowerPriority)`, kept at a very low priority instead."),
            .init("Animations", "The default content plays animated images. The Animated Images screen shows how.")
        ]
    )
}

#Preview {
    NavigationStack {
        LazyImageDemo()
    }
}
