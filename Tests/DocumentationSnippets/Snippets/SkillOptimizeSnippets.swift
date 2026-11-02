// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `skills/nuke-optimize/SKILL.md`, verbatim: `make llms` fails if a block
// in the skill is missing from this file.

import Foundation
import Nuke
import NukeUI
import SwiftUI

#if canImport(UIKit)
import UIKit

private struct Item: Identifiable {
    let id: Int
    let url: URL?
}

private struct Photo {
    let id: Int
}

// MARK: Measure

private func measure(url: URL) async throws {
    let pipeline = ImagePipeline { $0.isDiagnosticsEnabled = true }
    let task = pipeline.imageTask(with: url)
    _ = try await task.image
    print(task.metrics!.formatted([.header, .breakdown]))
}

// MARK: Decode less

private struct Cell: View {
    let url: URL?

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .processors([.resize(size: CGSize(width: 120, height: 120))]) // Points, aspect fill by default
        .frame(width: 120, height: 120)
        .clipped()
    }
}

private func thumbnail(url: URL) -> ImageRequest {
    var request = ImageRequest(url: url)
    request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 360) // Pixels, the longest side
    return request
}

// MARK: Cache keys

private func signed(signedURL: URL, photo: Photo) -> ImageRequest {
    var request = ImageRequest(url: signedURL, processors: [.resize(width: 320)])
    request.imageID = "photo-\(photo.id)" // Replaces the URL in the cache keys
    return request
}

// MARK: Disk cache

private func diskCache() {
    var configuration = ImagePipeline.Configuration.withDataCache(name: "com.example.images", sizeLimit: 500 * 1024 * 1024)
    configuration.dataCachePolicy = .automatic
    ImagePipeline.shared = ImagePipeline(configuration: configuration)
}

private func avatarRequest(url: URL) -> ImageRequest {
    var request = ImageRequest(url: url)
    request.cacheExpiration = .interval(120)
    return request
}

// MARK: Prefetching

private final class Grid: NSObject, UICollectionViewDataSourcePrefetching {
    var items: [Item] = []

    private let prefetcher = ImagePrefetcher()

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        prefetcher.startPrefetching(with: indexPaths.map { makeRequest(for: items[$0.item]) })
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        prefetcher.stopPrefetching(with: indexPaths.map { makeRequest(for: items[$0.item]) })
    }

    private func makeRequest(for item: Item) -> ImageRequest {
        ImageRequest(url: item.url, processors: [.resize(width: 120)])
    }
}

private struct Feed: View {
    let items: [Item]
    @State private var prefetcher = ImagePrefetcher()

    var body: some View {
        List(items.indices, id: \.self) { index in
            LazyImage(request: makeRequest(for: items[index]))
                .onAppear {
                    let next = items.dropFirst(index + 1).prefix(8)
                    prefetcher.startPrefetching(with: next.map(makeRequest))
                }
        }
    }

    private func makeRequest(for item: Item) -> ImageRequest {
        ImageRequest(url: item.url, processors: [.resize(width: 120)])
    }
}

// MARK: Load only what's on screen

private struct Reappearing: View {
    let url: URL?

    var body: some View {
        LazyImage(url: url)
            .onDisappear(.lowerPriority)
    }
}

private func reserveSlots() {
    ImagePipeline.shared = ImagePipeline {
        $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 6, reservedTaskCount: 4)
    }
}

// MARK: Animated images

private struct ResizeStills: ImageProcessing {
    let resize = ImageProcessors.Resize(width: 320)

    var identifier: String { "com.example.stills" + resize.identifier }

    func process(_ image: PlatformImage) -> PlatformImage? {
        resize.process(image)
    }

    func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
        guard container.animation == nil else { return container }
        return try resize.process(container, context: context)
    }
}

// MARK: Memory

private func memory() {
    ImageCache.shared.costLimit = 100 * 1024 * 1024
}

// MARK: The main thread

private func memoryOnly(request: ImageRequest) -> ImageContainer? {
    let cached = ImagePipeline.shared.cache.cachedImage(for: request, caches: [.memory])
    return cached
}

#endif
