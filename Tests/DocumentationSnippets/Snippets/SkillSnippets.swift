// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `skills/nuke/SKILL.md`, verbatim: `make llms` fails if a block in
// the skill is missing from this file. An agent copies them as they are, so a
// sample that doesn't compile is worse here than anywhere else.

import Foundation
import Nuke
import NukeTesting
import NukeUI
import SwiftUI

#if canImport(UIKit)
import UIKit

// MARK: SwiftUI

private struct Item: Identifiable {
    let id: Int
    let url: URL?
}

private struct Thumbnail: View {
    let url: URL?

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else if state.error != nil {
                Image(systemName: "photo")
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .processors([.resize(width: 120)]) // The size it's displayed at
        .frame(width: 120, height: 120)
        .clipped()
    }
}

private struct AnimatedContent: View {
    let url: URL?

    var body: some View {
        LazyImage(url: url) { state in
            if let container = state.imageContainer, let animation = AnimatedImage(container: container) {
                animation.resizable().scaledToFill()
            } else if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
    }
}

// MARK: UIKit

@MainActor
private enum UIKitSamples {
    static func cell(imageView: UIImageView, url: URL?) {
        ImageLoader.load(url, into: imageView, presentation: .init(
            placeholder: UIImage(named: "placeholder"),
            transition: .fadeIn(duration: 0.25),
            failureImage: UIImage(named: "error")
        ))
    }

    static func animated(url: URL?) {
        let imageView = AnimatedImageView()
        imageView.contentMode = .scaleAspectFill
        ImageLoader.load(url, into: imageView)
    }
}

private final class Prefetching: NSObject, UICollectionViewDataSourcePrefetching {
    private var items: [Item] = []
    private let prefetcher = ImagePrefetcher()

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        prefetcher.startPrefetching(with: indexPaths.map { makeRequest(for: items[$0.item]) })
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        prefetcher.stopPrefetching(with: indexPaths.map { makeRequest(for: items[$0.item]) })
    }

    // The cells must load the same request, or the image is loaded twice
    private func makeRequest(for item: Item) -> ImageRequest {
        ImageRequest(url: item.url, processors: [.resize(width: 120)])
    }
}

#endif

// MARK: Async

@MainActor
private enum AsyncSamples {
    static var progressBar = ImageTask.Progress(completed: 0, total: 0)
    static var image: PlatformImage?

    static func load(url: URL) async throws {
        let task = ImagePipeline.shared.imageTask(with: url)
        for await progress in task.progress {
            progressBar = progress // `fraction`, `completed`, `total`
        }
        image = try await task.image
    }

    static func handle(url: URL) async {
        do {
            image = try await ImagePipeline.shared.image(for: url)
        } catch {
            // `error` is an `ImagePipeline.Error`, no cast needed
            switch error {
            case .cancelled: break
            case .dataLoadingFailed(let underlying): print(underlying)
            default: print(error)
            }
        }
    }
}

// MARK: Setup

private func setup() {
    ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
}

private func customPipeline() {
    ImagePipeline.shared = ImagePipeline {
        $0.dataCache = try? DataCache(name: "com.example.images")
        $0.dataCachePolicy = .automatic
        $0.imageCache = ImageCache.shared
    }
}

// MARK: Requests

private func requests(url: URL) {
    var request = ImageRequest(url: url, processors: [.resize(width: 320)], priority: .high)
    request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 400) // Decodes small, without the full image
    request.imageID = "avatar-42" // The cache key, for a URL with a changing token
    request.options = [.disableDiskCacheWrites]
    _ = request
}

private struct Sepia: ImageProcessing {
    let identifier = "com.example.sepia" // Part of the cache key

    func process(_ image: PlatformImage) -> PlatformImage? {
        ImageProcessors.CoreImageFilter(name: "CISepiaTone").process(image)
    }
}

private func caches(url: URL, request: ImageRequest) {
    let pipeline = ImagePipeline.shared
    let cached = pipeline.cache[url] // The memory cache, synchronously
    pipeline.cache[request] = nil
    pipeline.cache.removeCachedImage(for: request) // From every layer
    pipeline.cache.removeAll()
    ImageCache.shared.costLimit = 200 * 1024 * 1024
    _ = cached
}

// MARK: Delegate

private final class PipelineDelegate: Sendable {}

extension PipelineDelegate: ImagePipeline.Delegate {
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        var urlRequest = urlRequest
        urlRequest.setValue("Bearer token", forHTTPHeaderField: "Authorization")
        return urlRequest
    }

    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline) async -> Data? {
        request.url?.path.hasPrefix("/private/") == true ? nil : data // `nil` keeps it off the disk
    }

    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        nil // `nil` uses the default key
    }

    func imageTaskDidStart(_ task: ImageTask, pipeline: ImagePipeline) {}

    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        switch event {
        case .progress(let progress): print(progress.fraction)
        case .preview(let response): print(response.image)
        case .finished(.failure(.cancelled)): break
        case .finished(let result): print(result)
        }
    }
}

private func installDelegate() {
    ImagePipeline.shared = ImagePipeline(delegate: PipelineDelegate()) {
        $0.dataCache = try? DataCache(name: "com.example.images")
    }
}

// MARK: Debugging

private func debugging(url: URL) async throws {
    let pipeline = ImagePipeline { $0.isDiagnosticsEnabled = true }
    let task = pipeline.imageTask(with: url)
    _ = try await task.image
    print(task.metrics!) // A timeline of the load

    print(await ImagePipeline.shared.diagnostics.snapshot())
}

// MARK: Testing

private func testing(url: URL, brokenURL: URL, offlineURL: URL, slowURL: URL, pageURL: URL) async throws {
    let dataLoader = StubDataLoader() // Every URL gets a generated image by default
    dataLoader.stub(brokenURL, with: .status(404))
    dataLoader.stub(offlineURL, with: .failure(URLError(.notConnectedToInternet)))
    dataLoader.stub(slowURL, with: .hanging)
    dataLoader.stub(pageURL, with: .data(Data("<html></html>".utf8), mimeType: "text/html"))

    let pipeline = ImagePipeline.stubbed(dataLoader) // No caches, so tests can't affect one another
    let image = try await pipeline.image(for: url)
    let requests = dataLoader.requests // What the code under test asked for
    _ = (image, requests)
}

#if canImport(UIKit)
private struct PreviewSample: View {
    let pipeline: ImagePipeline

    var body: some View {
        LazyImage(url: URL(string: "https://example.com/image.jpeg"))
            .pipeline(pipeline) // Only this view; `ImagePipeline.shared` is left alone
    }
}
#endif
