// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

private let pipeline = ImagePipeline.shared
private let url = URL(string: "https://example.com/image.jpeg")!
private let image = Test.image

// MARK: - Getting Started

private func checkGettingStarted01() async throws {
    let response = try await ImagePipeline.shared.image(for: url)
    let image = response.image

    _ = image
}

private final class CheckGettingStarted02: ImageTaskDelegate {
    func loadImage() async throws {
        let _ = try await pipeline.image(for: url, delegate: self)
    }

    func imageTaskCreated(_ task: ImageTask) {
        // Gets called immediately when the task is created.
    }

    func imageTask(_ task: ImageTask, didReceivePreview response: ImageResponse) {
        // Gets called for images that support progressive decoding.
    }

    func imageTask(_ task: ImageTask, didUpdateProgress progress: ImageTask.Progress) {
        // Gets called when the download progress is updated.
    }
}

private func checkGettingStarted03() async throws {
    let request = ImageRequest(
        url: URL(string: "http://example.com/image.jpeg"),
        processors: [.resize(width: 320)],
        priority: .high,
        options: [.reloadIgnoringCachedData]
    )
    let response = try await pipeline.image(for: request)

    _ = response
}

private func checkGettingStarted04() {
    ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
}

// MARK: - Access Cached Images

private func checkAccessCachedImages01() async throws {
    let request = ImageRequest(url: url, options: [.returnCacheDataDontLoad])
    let response = try await pipeline.image(for: request)
    let cacheType = response.cacheType // .memory, .disk, or nil

    _ = cacheType
}

private func checkAccessCachedImages02() {
    let request = ImageRequest(url: url)
    pipeline.cache.removeCachedImage(for: request)
}

private func checkAccessCachedImages03() async throws {
    let request = ImageRequest(url: url, options: [ .reloadIgnoringCachedData])
    let response = try await pipeline.image(for: request)

    _ = response
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
