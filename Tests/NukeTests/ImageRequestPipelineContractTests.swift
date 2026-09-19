// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

/// The documented contracts of ``ImageRequest`` and ``ImageResponse`` as the
/// pipeline observes them.
@Suite(.timeLimit(.minutes(5)))
struct ImageRequestPipelineContractTests {
    let dataLoader: MockDataLoader
    let imageCache: MockImageCache
    let dataCache: MockDataCache
    let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        let imageCache = MockImageCache()
        let dataCache = MockDataCache()
        self.dataLoader = dataLoader
        self.imageCache = imageCache
        self.dataCache = dataCache
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
        }
    }

    // MARK: - Missing URL

    /// "A `nil` URL produces a request that fails with `URLError(.badURL)`."
    @Test func requestWithoutURLFailsWithBadURL() async {
        // Given
        var urlRequest = URLRequest(url: Test.url)
        urlRequest.url = nil
        let requests: [ImageRequest] = [ImageRequest(url: nil), ImageRequest(urlRequest: urlRequest), ""]

        for request in requests {
            // When/Then
            do {
                _ = try await pipeline.image(for: request)
                Issue.record("Expected failure for \(request)")
            } catch {
                #expect((error.dataLoadingError as? URLError)?.code == .badURL)
            }
            do {
                _ = try await pipeline.data(for: request)
                Issue.record("Expected failure for \(request)")
            } catch {
                #expect((error.dataLoadingError as? URLError)?.code == .badURL)
            }
        }

        // Then the data loader is never asked and nothing is cached
        #expect(dataLoader.createdTaskCount == 0)
        #expect(imageCache.writeCount == 0)
        #expect(dataCache.writeCount == 0)
    }

    // MARK: - Image ID Override

    /// The override identifies the image for the caches, but the URL is what
    /// gets loaded.
    @Test func imageIDOverrideDoesNotRedirectDownload() async throws {
        // Given the second URL fails to load
        let pipeline = pipeline.reconfigured {
            $0.imageCache = nil
            $0.dataCache = nil
        }
        let first = try Self.makeTokenizedRequest(token: "1")
        let second = try Self.makeTokenizedRequest(token: "2")
        let failingURL = try #require(second.url)
        dataLoader.results[failingURL] = .failure(URLError(.notConnectedToInternet) as NSError)

        // When/Then
        _ = try await pipeline.image(for: first)
        do {
            _ = try await pipeline.image(for: second)
            Issue.record("Expected the second URL to be loaded")
        } catch {
            #expect((error.dataLoadingError as? URLError)?.code == .notConnectedToInternet)
        }
        #expect(dataLoader.createdTaskCount == 2)
    }

    private static func makeTokenizedRequest(token: String) throws -> ImageRequest {
        let url = try #require(URL(string: "https://example.com/image.jpeg?token=\(token)"))
        var request = ImageRequest(url: url)
        request.imageID = "https://example.com/image.jpeg"
        return request
    }

    // MARK: - Closure Requests

    /// The ID identifies the image: another closure under the same ID is
    /// served from the cache and never runs.
    @Test func closureRequestIsCachedUnderItsID() async throws {
        // Given
        let calls = OSAllocatedUnfairLock(initialState: 0)
        _ = try await pipeline.image(for: ImageRequest(id: "photo-1", data: {
            calls.withLock { $0 += 1 }
            return Test.data
        }))

        // When
        let response = try await pipeline.imageTask(with: ImageRequest(id: "photo-1", data: {
            Issue.record("The cached image was expected")
            return Test.data
        })).response

        // Then
        #expect(response.cacheType == .memory)
        #expect(calls.withLock { $0 } == 1)
    }

    /// "Use `disableDiskCache` to prevent this."
    @Test func closureDataIsNotStoredWithDiskCacheDisabled() async throws {
        // When
        _ = try await pipeline.image(for: ImageRequest(id: "photo-1", data: { Test.data }, options: [.disableDiskCache]))

        // Then
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.readCount == 0)
        #expect(imageCache.writeCount == 1)
    }

    @Test func closureImageIsCachedUnderItsID() async throws {
        // Given
        _ = try await pipeline.image(for: ImageRequest(id: "photo-1", image: { Test.container }))

        // When
        let response = try await pipeline.imageTask(with: ImageRequest(id: "photo-1", image: {
            Issue.record("The cached image was expected")
            return Test.container
        })).response

        // Then
        #expect(response.cacheType == .memory)
    }

    // MARK: - ImageResponse

    /// "`nil` unless the resource was fetched from the network or an HTTP cache."
    @Test func urlResponseIsSetForNetworkLoadOnly() async throws {
        // When loaded from the network
        let network = try await pipeline.imageTask(with: Test.request).response

        // Then
        #expect(network.cacheType == nil)
        #expect(network.urlResponse?.url == Test.url)

        // When loaded from the memory cache
        let memory = try await pipeline.imageTask(with: Test.request).response

        // Then
        #expect(memory.cacheType == .memory)
        #expect(memory.urlResponse == nil)
    }

    @Test func urlResponseIsNilForDiskCacheHit() async throws {
        // Given
        let pipeline = pipeline.reconfigured { $0.imageCache = nil }
        dataCache.store[Test.url.absoluteString] = Test.data

        // When
        let response = try await pipeline.imageTask(with: Test.request).response

        // Then
        #expect(response.cacheType == .disk)
        #expect(response.urlResponse == nil)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func urlResponseIsNilForClosureRequest() async throws {
        // When
        let response = try await pipeline.imageTask(with: ImageRequest(id: "photo-1", data: { Test.data })).response

        // Then
        #expect(response.cacheType == nil)
        #expect(response.urlResponse == nil)
    }

    /// The response carries the request that produced it, including the
    /// metadata that doesn't affect loading.
    ///
    /// - note: The request has no processors: a processed image loaded from
    /// the network carries the request without them – reported as a suspected
    /// bug.
    @Test func responseCarriesRequestItWasCreatedFor() async throws {
        // Given
        var request = ImageRequest(url: Test.url, priority: .high)
        request.userInfo[.labelKey] = "feed"
        request.imageID = "custom-id"

        // When
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.request.url == Test.url)
        #expect(response.request.imageID == "custom-id")
        #expect(response.request.priority == .high)
        #expect(response.request.userInfo[.labelKey] as? String == "feed")
    }

    @Test func memoryCacheHitCarriesRequestWithProcessors() async throws {
        // Given
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
        imageCache[request] = Test.container

        // When
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.cacheType == .memory)
        #expect(response.request.processors.map(\.identifier) == ["p1"])
        #expect(dataLoader.createdTaskCount == 0)
    }
}
