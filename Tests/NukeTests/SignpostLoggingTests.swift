// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// Signpost logging is off by default, which leaves the instrumentation in the
/// pipeline unexercised. These run the common paths with it enabled to make sure
/// the instrumented code behaves exactly like the uninstrumented one.
///
/// - note: Serialized because `isSignpostLoggingEnabled` is a global setting.
@Suite(.timeLimit(.minutes(5)), .serialized)
struct SignpostLoggingTests {
    private let dataLoader: MockDataLoader
    private let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    @Test func imageIsLoadedWithSignpostLoggingEnabled() async throws {
        // Given
        ImagePipeline.Configuration.isSignpostLoggingEnabled = true
        defer { ImagePipeline.Configuration.isSignpostLoggingEnabled = false }

        // When
        let image = try await pipeline.image(for: Test.request)

        // Then
        #expect(image.sizeInPixels == CGSize(width: 640, height: 480))
    }

    @Test func processedImageIsLoadedWithSignpostLoggingEnabled() async throws {
        // Given
        ImagePipeline.Configuration.isSignpostLoggingEnabled = true
        defer { ImagePipeline.Configuration.isSignpostLoggingEnabled = false }

        let request = ImageRequest(url: Test.url, processors: [
            .resize(size: CGSize(width: 320, height: 240), unit: .pixels)
        ])

        // When
        let image = try await pipeline.image(for: request)

        // Then
        #expect(image.sizeInPixels == CGSize(width: 320, height: 240))
    }

    @Test func cancellationIsLoggedWithSignpostLoggingEnabled() async throws {
        // Given
        ImagePipeline.Configuration.isSignpostLoggingEnabled = true
        defer { ImagePipeline.Configuration.isSignpostLoggingEnabled = false }

        dataLoader.isSuspended = true
        let task = await withSuspendedDataLoading(for: pipeline, expectedCount: 1) {
            pipeline.imageTask(with: Test.request)
        }

        // When
        task.cancel()

        // Then
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }
    }

    /// The pipeline reads `isSignpostLoggingEnabled` on every `signpost(...)`
    /// call from its own threads, so writing it from another thread has to be
    /// synchronized – otherwise the thread sanitizer aborts the test run.
    @Test func signpostLoggingIsToggledWhileLoadingImages() async throws {
        // Given
        let initialValue = ImagePipeline.Configuration.isSignpostLoggingEnabled
        defer { ImagePipeline.Configuration.isSignpostLoggingEnabled = initialValue }

        let writer = Task.detached {
            var isEnabled = true
            while !Task.isCancelled {
                isEnabled.toggle()
                ImagePipeline.Configuration.isSignpostLoggingEnabled = isEnabled
                await Task.yield()
            }
        }

        // When loading images while the flag is being toggled
        let pipeline = self.pipeline
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask {
                    let url = URL(string: "https://example.com/image-\(index).jpeg")!
                    _ = try? await pipeline.image(for: ImageRequest(url: url))
                }
            }
        }

        // Then no data races are reported
        writer.cancel()
        await writer.value
    }

    @Test func byteFormatter() {
        #expect(!Formatter.bytes(0).isEmpty)
        #expect(!Formatter.bytes(1024).isEmpty)
        #expect(Formatter.bytes(Int64(2048)) == Formatter.bytes(2048))
    }
}
