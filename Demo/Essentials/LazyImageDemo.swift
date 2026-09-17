// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI

/// Demonstrates ``LazyImage`` – the SwiftUI view for displaying remote images –
/// and ``FetchImage``, the observable object it is built on, for a view of
/// your own.
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
                    DemoExample("Default", caption: "LazyImage(url:) displays the image at its natural size, and a gray fill until then, or instead if it fails") {
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
                            } else if state.error != nil {
                                DemoFailureView()
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
                                        Circle()
                                            .fill(Color(.secondarySystemBackground))
                                            .overlay {
                                                if state.error != nil {
                                                    Image(systemName: "exclamationmark.triangle")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
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
                            } else if state.error != nil {
                                DemoFailureView()
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
                                lastResult = "Failed: \(error.demoSummary)"
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

                    DemoExample("FetchImage", caption: "The observable object LazyImage is built on, in a view of your own") {
                        FetchImageExample(url: DemoImages.photos[4])
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

        // A view of your own
        @StateObject var image = FetchImage()

        var body: some View {
            ZStack {
                image.image?.resizable()
            }
            .onAppear { image.load(url) }
        }
        """,
        points: [
            .init("States", "The closure receives a `LazyImageState` with the image, the error, and the download progress. Without a closure the view displays the image and nothing else."),
            .init("Transitions", "Pass a `Transaction` to animate the change from the placeholder to the image."),
            .init("Processors", "`.processors(_:)` attaches them to the request. The processed image is cached, so the work is done once."),
            .init("Priority", "`.priority(.high)` raises the priority of the request. When the view disappears the request is cancelled, or, with `.onDisappear(.lowerPriority)`, kept at a very low priority instead."),
            .init("Animations", "The default content plays animated images. The Animated Images screen shows how."),
            .init("Failures", "`state.error` is set when a load fails; the default content shows the same gray fill as while loading, so a view that can fail wants a closure. The Failure example loads a URL that answers 404."),
            .init("FetchImage", "`LazyImage` keeps its state in a `FetchImage`, and a view of your own can keep one too, as a `@StateObject`. It publishes `image`, `result`, and `isLoading`; `progress` is published only once a view has read it, so a view without a progress bar isn't redrawn for every chunk. `load(_:)` starts a request, `cancel()` stops it and keeps the image, and `reset()` clears everything. `priority` can change while the request runs."),
            .init("Your own call", "`FetchImage.load(_:)` also takes an async closure that returns an `ImageResponse`, for an image that needs a call of your own first, such as one for a signed URL. An error it throws is reported as `dataLoadingFailed`.")
        ]
    )
}

/// A view of its own around ``FetchImage``: the image, a progress bar, the
/// result in words, and buttons that drive the object directly – what
/// `LazyImage` does for you, spelled out.
private struct FetchImageExample: View {
    let url: URL

    @StateObject private var image = FetchImage()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let view = image.image {
                    view.resizable().scaledToFill()
                } else if image.error != nil {
                    DemoFailureView()
                } else {
                    Color(.secondarySystemBackground)
                }
            }
            .frame(height: 180)
            .clipped()
            .overlay(alignment: .bottom) {
                if image.isLoading {
                    // Reading `progress` is what makes the object publish it.
                    ProgressView(value: image.progress.fraction)
                        .padding(8)
                }
            }

            HStack(spacing: 8) {
                DemoMonoLabel(status, tint: image.error == nil ? nil : .red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Button("Load") { image.load(url) }
                Button("Reset") { image.reset() }
                    .disabled(image.result == nil && !image.isLoading)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .onAppear {
            if image.result == nil, !image.isLoading {
                image.load(url)
            }
        }
    }

    private var status: String {
        if image.isLoading {
            let progress = image.progress
            return progress.total > 0 ? "loading · \(demoByteCount(progress.completed)) of \(demoByteCount(progress.total))" : "loading"
        }
        switch image.result {
        case nil:
            return "reset · nothing loaded"
        case .success(let response)?:
            switch response.cacheType {
            case .memory?: return "memory cache"
            case .disk?: return "disk cache"
            case nil: return DemoFixture.isFixture(response.request.url) ? "fixture loader" : "network or URLCache"
            }
        case .failure(let error)?:
            return "failed · \(error.demoSummary)"
        }
    }
}

#Preview {
    NavigationStack {
        LazyImageDemo()
    }
}
