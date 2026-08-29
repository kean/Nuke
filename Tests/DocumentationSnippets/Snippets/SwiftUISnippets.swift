// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Essentials/swiftui.md`.
//
// This target exists only to make the hand-written samples in the articles
// compile. If a snippet here stops building, the article is out of date.

import SwiftUI
import NukeUI

// MARK: - LazyImage

private struct AvatarView: View {
    let url: URL

    var body: some View {
        LazyImage(url: url)
            .frame(width: 80, height: 80)
            .clipShape(Circle())
    }
}

// MARK: - Handling Loading and Failure States

private struct StatesView: View {
    let url: URL

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else if state.error != nil {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .frame(width: 320, height: 200)
        .clipped()
    }
}

// MARK: - Transitions

private struct TransitionView: View {
    let url: URL

    var body: some View {
        LazyImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.33))) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
    }
}

// MARK: - Image Processors

private struct ProcessorsView: View {
    let url: URL

    var body: some View {
        LazyImage(request: ImageRequest(
            url: url,
            processors: [.resize(width: 320)]
        ))
    }
}

private struct ViewProcessorsView: View {
    let url: URL

    var body: some View {
        LazyImage(url: url)
            .processors([.resize(width: 320)])
            .priority(.high)
    }
}

// MARK: - Using a Custom Pipeline

private struct CustomPipelineView: View {
    let url: URL
    let myPipeline: ImagePipeline

    var body: some View {
        LazyImage(url: url)
            .pipeline(myPipeline)
    }
}

// MARK: - FetchImage for Custom Views

private struct CustomImageView: View {
    let url: URL
    @StateObject private var fetchImage = FetchImage()

    var body: some View {
        ZStack {
            fetchImage.image?
                .resizable()
                .scaledToFill()

            if fetchImage.isLoading {
                ProgressView()
            }
        }
        .onAppear { fetchImage.load(url) }
        .onDisappear { fetchImage.reset() }
    }
}
