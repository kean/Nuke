// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// The pipeline reads `file://` and `data:` URLs directly instead of going
/// through the ``DataLoading`` stack.
///
/// - seealso: ``ImagePipeline/Configuration-swift.struct/isLocalResourcesSupportEnabled``
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineLocalResourcesTests {
    private let dataLoader: MockDataLoader
    private let dataCache: MockDataCache
    private let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        self.dataLoader = dataLoader
        self.dataCache = dataCache
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.dataCachePolicy = .storeOriginalData
            $0.imageCache = nil
        }
    }

    // MARK: - File URLs

    @Test func imageIsLoadedFromFileURLWithoutUsingTheDataLoader() async throws {
        // Given
        let url = try makeTemporaryFile(with: Test.data)
        defer { try? FileManager.default.removeItem(at: url) }

        // When
        let image = try await pipeline.image(for: ImageRequest(url: url))

        // Then
        #expect(image.sizeInPixels == CGSize(width: 640, height: 480))
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func missingFileFailsWithDataLoadingFailed() async throws {
        // Given a URL pointing at a file that doesn't exist
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nuke-missing-\(UUID().uuidString).jpeg")

        // When
        do {
            _ = try await pipeline.image(for: ImageRequest(url: url))
            Issue.record("Expected the request to fail")
        } catch {
            // Then the underlying file system error is preserved
            guard case .dataLoadingFailed(let underlying) = error else {
                Issue.record("Expected dataLoadingFailed, got \(error)")
                return
            }
            #expect((underlying as NSError).domain == NSCocoaErrorDomain)
            #expect((underlying as NSError).code == NSFileReadNoSuchFileError)
        }
        #expect(dataLoader.createdTaskCount == 0)
    }

    /// An empty local resource fails the way an empty download does, instead
    /// of succeeding with no data, or failing in the decoder.
    @Test func emptyFileFailsWithDataIsEmpty() async throws {
        // Given
        let url = try makeTemporaryFile(with: Data())
        defer { try? FileManager.default.removeItem(at: url) }

        // When/Then
        await #expect(throws: ImagePipeline.Error.dataIsEmpty) {
            try await pipeline.data(for: ImageRequest(url: url))
        }
        await #expect(throws: ImagePipeline.Error.dataIsEmpty) {
            try await pipeline.image(for: ImageRequest(url: url))
        }
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func fileURLIsNotStoredInTheDataCache() async throws {
        // Given
        let url = try makeTemporaryFile(with: Test.data)
        defer { try? FileManager.default.removeItem(at: url) }

        // When
        _ = try await pipeline.image(for: ImageRequest(url: url))

        // Then the local file isn't copied into the disk cache
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.isEmpty)
    }

    // MARK: - Data URLs

    @Test func imageIsLoadedFromDataURLWithoutUsingTheDataLoader() async throws {
        // Given
        let url = try #require(URL(string: "data:image/jpeg;base64,\(Test.data.base64EncodedString())"))

        // When
        let image = try await pipeline.image(for: ImageRequest(url: url))

        // Then
        #expect(image.sizeInPixels == CGSize(width: 640, height: 480))
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func malformedDataURLFailsWithDataLoadingFailed() async throws {
        // Given
        let url = try #require(URL(string: "data:image/jpeg;base64,~~~not-base64~~~"))

        // When
        do {
            _ = try await pipeline.image(for: ImageRequest(url: url))
            Issue.record("Expected the request to fail")
        } catch {
            // Then
            guard case .dataLoadingFailed = error else {
                Issue.record("Expected dataLoadingFailed, got \(error)")
                return
            }
        }
    }

    @Test func emptyDataURLFailsWithDataIsEmpty() async throws {
        // Given
        let url = try #require(URL(string: "data:image/jpeg;base64,"))

        // When/Then
        await #expect(throws: ImagePipeline.Error.dataIsEmpty) {
            try await pipeline.data(for: ImageRequest(url: url))
        }
        await #expect(throws: ImagePipeline.Error.dataIsEmpty) {
            try await pipeline.image(for: ImageRequest(url: url))
        }
        #expect(dataLoader.createdTaskCount == 0)
    }

    // MARK: - Case-Insensitive Schemes

    /// URI schemes are case-insensitive (RFC 3986), so `FILE://` has to be
    /// treated exactly like `file://`.
    @Test func uppercaseFileURLIsLoadedDirectlyAndIsNotStoredInTheDataCache() async throws {
        // Given
        let fileURL = try makeTemporaryFile(with: Test.data)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let path = fileURL.absoluteString.dropFirst("file://".count)
        let url = try #require(URL(string: "FILE://" + path))

        // When
        let image = try await pipeline.image(for: ImageRequest(url: url))

        // Then
        #expect(image.sizeInPixels == CGSize(width: 640, height: 480))
        #expect(dataLoader.createdTaskCount == 0)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.isEmpty)
    }

    @Test func uppercaseDataURLIsLoadedDirectlyAndIsNotStoredInTheDataCache() async throws {
        // Given
        let url = try #require(URL(string: "DATA:image/jpeg;base64,\(Test.data.base64EncodedString())"))

        // When
        let image = try await pipeline.image(for: ImageRequest(url: url))

        // Then
        #expect(image.sizeInPixels == CGSize(width: 640, height: 480))
        #expect(dataLoader.createdTaskCount == 0)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.isEmpty)
    }

    // MARK: - Disabling Local Resources Support

    @Test func localResourcesGoThroughTheDataLoaderWhenSupportIsDisabled() async throws {
        // Given
        let pipeline = pipeline.reconfigured {
            $0.isLocalResourcesSupportEnabled = false
        }
        let url = try makeTemporaryFile(with: Test.data)
        defer { try? FileManager.default.removeItem(at: url) }

        // When
        _ = try await pipeline.image(for: ImageRequest(url: url))

        // Then
        #expect(dataLoader.createdTaskCount == 1)
    }

    /// Even when the data is fetched by the data loader, a local resource is
    /// never worth duplicating in the disk cache.
    @Test func localResourceIsNotStoredInTheDataCacheWhenSupportIsDisabled() async throws {
        // Given
        let pipeline = pipeline.reconfigured {
            $0.isLocalResourcesSupportEnabled = false
        }
        let url = try makeTemporaryFile(with: Test.data)
        defer { try? FileManager.default.removeItem(at: url) }

        // When
        _ = try await pipeline.image(for: ImageRequest(url: url))

        // Then
        #expect(dataLoader.createdTaskCount == 1)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.isEmpty)
    }

    @Test func remoteResourcesAreStillStoredInTheDataCache() async throws {
        // When
        _ = try await pipeline.image(for: Test.request)

        // Then
        #expect(dataCache.writeCount == 1)
    }

    // MARK: - Loading Data

    /// A data task returns the contents of the file as is: it never decodes
    /// them, and there is no `URLResponse` for a file read inline.
    @Test func dataForFileURLReturnsTheContentsOfTheFile() async throws {
        // Given a file that isn't an image
        let bytes = Data("not an image".utf8)
        let url = try makeTemporaryFile(with: bytes)
        defer { try? FileManager.default.removeItem(at: url) }

        // When
        let (data, response) = try await pipeline.data(for: ImageRequest(url: url))

        // Then
        #expect(data == bytes)
        #expect(response == nil)
        #expect(dataLoader.createdTaskCount == 0)
        #expect(dataCache.writeCount == 0)
    }

    @Test(arguments: [
        (URL(string: "data:text/plain;base64,\(Data("hello, world".utf8).base64EncodedString())")!, "hello, world"),
        (URL(string: "data:text/plain,hello%2C%20world")!, "hello, world")
    ])
    func dataForDataURLReturnsTheDecodedPayload(url: URL, payload: String) async throws {
        // When
        let (data, response) = try await pipeline.data(for: ImageRequest(url: url))

        // Then
        #expect(data == Data(payload.utf8))
        #expect(response == nil)
        #expect(dataLoader.createdTaskCount == 0)
        #expect(dataCache.writeCount == 0)
    }

    /// The local resources are read without going through the data loading
    /// queue, so they load even when the queue is suspended.
    @Test func localResourceDoesNotWaitForTheDataLoadingQueue() async throws {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        defer { queue.isSuspended = false }
        let url = try #require(URL(string: "data:image/jpeg;base64,\(Test.data.base64EncodedString())"))

        // When
        let (data, _) = try await pipeline.data(for: ImageRequest(url: url))

        // Then
        #expect(data == Test.data)
    }

    // MARK: - Helpers

    private func makeTemporaryFile(with data: Data) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nuke-local-resource-\(UUID().uuidString).jpeg")
        try data.write(to: url)
        return url
    }
}
