// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Essentials/replacing-async-image.md`.
//
// This target exists only to make the hand-written samples in the articles
// compile. If a snippet here stops building, the article is out of date.

import SwiftUI
import NukeUI

// MARK: - The Common Case

private struct CommonCaseViews: View {
    let url: URL

    var body: some View {
        // AsyncImage
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Image(systemName: "photo")
            case .empty:
                ProgressView()
            @unknown default:
                EmptyView()
            }
        }

        // LazyImage
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else if state.error != nil {
                Image(systemName: "photo")
            } else {
                ProgressView()
            }
        }
    }
}

private struct PlaceholderViews: View {
    let url: URL

    var body: some View {
        // AsyncImage
        AsyncImage(url: url) { image in
            image.resizable()
        } placeholder: {
            ProgressView()
        }

        // LazyImage
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable()
            } else {
                ProgressView()
            }
        }
    }
}

// MARK: - Initializers

private struct ScaleView: View {
    let url: URL

    var body: some View {
        let request = {
            var request = ImageRequest(url: url)
            request.scale = 3
            return request
        }()

        LazyImage(request: request) { state in
            if let image = state.image {
                image
            }
        }
    }
}

private struct URLRequestView: View {
    let urlRequest: URLRequest

    var body: some View {
        LazyImage(request: ImageRequest(urlRequest: urlRequest)) { state in
            if let image = state.image {
                image
            }
        }
    }
}

// MARK: - Setting the Session

private struct SessionView: View {
    let token: String

    var body: some View {
        let configuration = DataLoader.defaultConfiguration
        configuration.httpAdditionalHeaders = ["Authorization": "Bearer \(token)"]

        let pipeline = ImagePipeline {
            $0.dataLoader = DataLoader(configuration: configuration)
        }

        return ContentView()
            .imagePipeline(pipeline)
    }
}

private struct ContentView: View {
    var body: some View { EmptyView() }
}

// MARK: - Code That Takes a Phase

extension LazyImageState {
    var phase: AsyncImagePhase {
        if let image {
            .success(image)
        } else if let error {
            .failure(error)
        } else {
            .empty
        }
    }
}

private struct PhaseView: View {
    let url: URL

    var body: some View {
        LazyImage(url: url) { state in
            AvatarContent(phase: state.phase)
        }
    }
}

private struct AvatarContent: View {
    let phase: AsyncImagePhase

    var body: some View {
        phase.image ?? Image(systemName: "person")
    }
}
