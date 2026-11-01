// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Essentials/coming-from-other-libraries.md`.
//
// The right column of the tables, so that a row can't name an API that doesn't
// exist. The recipes it points to are in `RecipesSnippets.swift`.

import Foundation
import Nuke
import NukeUI
import SwiftUI
import UIKit

private func withDataCache() {
    ImagePipeline.shared = ImagePipeline(configuration: .withDataCache())
}

private struct AsyncImageViews: View {
    let url: URL

    var body: some View {
        // AsyncImage
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable()
            case .failure: Color.red
            default: ProgressView()
            }
        }

        // Nuke
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable()
            } else if state.error != nil {
                Color.red
            } else {
                ProgressView()
            }
        }
    }
}

private struct Views: View {
    let url: URL

    var body: some View {
        LazyImage(url: url)
        LazyImage(url: url) { state in
            if let image = state.image { image } else if state.error != nil { Color.red }
        }
        LazyImage(url: url, transaction: Transaction(animation: .easeIn)) { state in
            state.image
        }
        LazyImage(url: url)
            .onCompletion { _ in }
            .onDisappear(.cancel)
            .pipeline(ImagePipeline.shared)
        LazyImage(request: ImageRequest(urlRequest: URLRequest(url: url)))
    }
}

@MainActor
private func imageViews(url: URL, imageView: UIImageView, animatedImageView: AnimatedImageView) {
    ImageLoader.load(url, into: imageView)
    ImageLoader.loader(for: imageView).cancel()
    ImageLoader.load(url, into: animatedImageView)
    _ = ImageLoader.Presentation(transition: .fadeIn(duration: 0.33))
}

private func pipeline(url: URL, urls: [URL]) async throws {
    _ = try await ImagePipeline.shared.image(for: url)
    ImagePrefetcher().startPrefetching(with: urls)
    _ = ImagePipeline.shared.cache
    _ = DataLoader()
    let dataLoading: any DataLoading = DataLoader()
    _ = dataLoading
}

private final class RequestModifier: Sendable {}

extension RequestModifier: ImagePipeline.Delegate {
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        urlRequest
    }
}

private func requests(url: URL) {
    var request = ImageRequest(url: url, processors: [
        .roundedCorners(radius: 8),
        .gaussianBlur(radius: 8),
        .resize(size: CGSize(width: 320, height: 320))
    ])
    request.options = [.reloadIgnoringCachedData]
    request.options = [.returnCacheDataDontLoad]
    request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
    request.scale = 2
}

private func configuration() throws {
    let imageCache = ImageCache()
    imageCache.costLimit = 1024 * 1024 * 100
    imageCache.ttl = 60

    let dataCache = try DataCache(name: "com.example.images")
    dataCache.sizeLimit = 1024 * 1024 * 150

    var configuration = ImagePipeline.Configuration()
    configuration.isProgressiveDecodingEnabled = true

    _ = ImageDecoderRegistry.shared.register { _ in nil }
}
