// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

#if os(iOS) || os(visionOS)

import UIKit

private let pipeline = ImagePipeline.shared
private let url = URL(string: "https://example.com/image.jpeg")!
private let image = Test.image
private let data = Test.data
private let imageView = UIImageView()

// MARK: - Getting Started

private func checkGettingStarted01() async throws {
    let image = try await ImagePipeline.shared.image(for: url)
    _ = image
}

private final class CheckGettingStarted02 {
    @MainActor
    func loadImage() async throws {
        let imageTask = ImagePipeline.shared.imageTask(with: url)
        for await progress in imageTask.progress {
            // Update progress
            _ = progress
        }
        imageView.image = try await imageTask.image
    }
}

private func checkGettingStarted03() async throws {
    let request = ImageRequest(
        url: URL(string: "http://example.com/image.jpeg"),
        processors: [.resize(width: 320)],
        priority: .high,
        options: [.reloadIgnoringCachedData]
    )
    let image = try await pipeline.image(for: request)

    _ = image
}

private func checkGettingStarted04() {
    ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
}

// MARK: - Access Cached Images

private func checkAccessCachedImages01() async throws {
    let request = ImageRequest(url: url, options: [.returnCacheDataDontLoad])
    let response = try await pipeline.imageTask(with: request).response
    let cacheType = response.cacheType // .memory, .disk, or nil

    _ = cacheType
}

private func checkAccessCachedImages02() {
    let request = ImageRequest(url: url)
    pipeline.cache.removeCachedImage(for: request)
}

private func checkAccessCachedImages03() async throws {
    let request = ImageRequest(url: url, options: [ .reloadIgnoringCachedData])
    let image = try await pipeline.image(for: request)

    _ = image
}

private func checkAccessCachedImages04() {
    let image = pipeline.cache[URL(string: "https://example.com/image.jpeg")!]
    pipeline.cache[ImageRequest(url: url)] = nil

    _ = image
}

private func checkAccessCachedImages05() {
    let url = URL(string: "https://example.com/image.jpeg")!
    pipeline.cache[url] = ImageContainer(image: image)

    // Returns `nil` because memory cache reads are disabled
    let request = ImageRequest(url: url, options: [.disableMemoryCacheWrites])
    let image = pipeline.cache[request]

    _ = image
}

private func checkAccessCachedImages06() {
    let cache = pipeline.cache
    let request = ImageRequest(url: URL(string: "https://example.com/image.jpeg")!)

    _ = cache.cachedImage(for: request) // From any cache layer
    _ = cache.cachedImage(for: request, caches: [.memory]) // Only memory
    _ = cache.cachedImage(for: request, caches: [.disk]) // Only disk (decodes data)

    let data = cache.cachedData(for: request)
    _ = cache.containsData(for: request) // Fast contains check

    // Stores image in the memory cache and stores an encoded
    // image in the disk cache
    cache.storeCachedImage(ImageContainer(image: image), for: request)

    cache.removeCachedImage(for: request)
    cache.removeAll()

    _ = data
}

private func checkAccessCachedImages07() {
    let request = ImageRequest(url: URL(string: "https://example.com/image.jpeg"))
    _ = pipeline.cache.makeImageCacheKey(for: request)
    _ = pipeline.cache.makeDataCacheKey(for: request)
}

private final class CheckAccessCachedImages08: ImagePipelineDelegate {
    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        request.userInfo["imageId"] as? String
    }
}

// MARK: - Cache Configuration

private func checkCacheConfiguration01() {
    ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
}

// MARK: - Cache Layers

private func checkCacheLayers01() {
    // Configure cache
    ImageCache.shared.costLimit = 1024 * 1024 * 100 // 100 MB
    ImageCache.shared.countLimit = 100
    ImageCache.shared.ttl = 120 // Invalidate image after 120 sec

    // Read and write images
    let request = ImageRequest(url: url)
    ImageCache.shared[request] = ImageContainer(image: image)
    let image = ImageCache.shared[request]

    // Clear cache
    ImageCache.shared.removeAll()

    _ = image
}

private func checkCacheLayers02() {
    // Configure cache
    DataLoader.sharedUrlCache.diskCapacity = 100
    DataLoader.sharedUrlCache.memoryCapacity = 0

    // Read and write responses
    let urlRequest = URLRequest(url: url)
    _ = DataLoader.sharedUrlCache.cachedResponse(for: urlRequest)
    DataLoader.sharedUrlCache.removeCachedResponse(for: urlRequest)

    // Clear cache
    DataLoader.sharedUrlCache.removeAllCachedResponses()
}

private func checkCacheLayers03() {
    _ = ImagePipeline {
        $0.dataCache = try? DataCache(name: "com.myapp.datacache")
    }
}

private func checkCacheLayers04() throws {
    let dataCache = try DataCache(name: "my-cache")

    dataCache.sizeLimit = 1024 * 1024 * 100 // 100 MB

    dataCache.storeData(data, for: "key")
    if dataCache.containsData(for: "key") {
        print("Data is cached")
    }
    let data = dataCache.cachedData(for: "key")
    // or let data = dataCache["key"]
    dataCache.removeData(for: "key")
    dataCache.removeAll()

    _ = data
}

private func checkCacheLayers05() throws {
    let dataCache = try DataCache(name: "my-cache")

    dataCache.storeData(data, for: "key")
    dataCache.flush()
    // or dataCache.flush(for: "key")

    let url = dataCache.url(for: "key")
    // Access file directly
    _ = url
}

// MARK: - Performance

private func checkPerformance01() {
    // Target size is in points.
    let request = ImageRequest(
        url: URL(string: "http://..."),
        processors: [.resize(width: 320)]
    )

    _ = request
}

private func checkPerformance02() {
    final class ImageView: UIView {
        private var task: ImageTask?

        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)

            task?.priority = newWindow == nil ? .low : .high
        }
    }
}

private func checkPerformance03() async throws {
    let url = URL(string: "http://example.com/image")
    async let first = pipeline.image(for: ImageRequest(url: url, processors: [
        .resize(size: CGSize(width: 44, height: 44)),
        .gaussianBlur(radius: 8)
    ]))
    async let second = pipeline.image(for: ImageRequest(url: url, processors: [
        .resize(size: CGSize(width: 44, height: 44))
    ]))
    let images = try await (first, second)

    _ = images
}

// MARK: - Prefetching

private final class PrefetchingDemoViewController: UICollectionViewController {
    private let prefetcher = ImagePrefetcher()
    private var photos: [URL] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView?.isPrefetchingEnabled = true
        collectionView?.prefetchDataSource = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        prefetcher.isPaused = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // When you pause, the prefetcher will finish outstanding tasks
        // (by default, there are only 2 at a time), and pause the rest.
        prefetcher.isPaused = true
    }
}

extension PrefetchingDemoViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.map { photos[$0.row] }
        prefetcher.startPrefetching(with: urls)
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.map { photos[$0.row] }
        prefetcher.startPrefetching(with: urls)
    }
}

// MARK: - ImagePipeline (Extension)

private func checkImagePipelineExtension01() {
    _ = ImagePipeline {
        $0.dataCache = try? DataCache(name: "com.myapp.datacache")
        $0.dataCachePolicy = .automatic
    }
}

private func checkImagePipelineExtension02() async throws {
    let image = try await ImagePipeline.shared.image(for: url)
    _ = image
}

private final class AsyncImageView: UIImageView {
    func loadImage() async throws {
        let imageTask = ImagePipeline.shared.imageTask(with: url)
        for await progress in imageTask.progress {
            // Update progress
            _ = progress
        }
        imageView.image = try await imageTask.image
    }
}
#endif
