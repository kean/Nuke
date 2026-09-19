// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
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

    /// Zero is a number, not "Zero KB": the records print it next to other
    /// byte counts.
    @Test func byteFormatterPrintsZeroAsANumber() {
        #expect(Formatter.bytes(0).hasPrefix("0"), "\(Formatter.bytes(0))")
    }

    /// The pipeline builds a message for every data load, so it is built
    /// only when there is a log to write it to.
    @Test func messageIsBuiltOnlyWhenLoggingIsEnabled() {
        // Given
        var count = 0
        func message() -> String {
            count += 1
            return "message"
        }
        let object = NSObject()

        // When logging is disabled
        ImagePipeline.Configuration.isSignpostLoggingEnabled = false
        signpost(object, "Test", .event, message())

        // Then
        #expect(count == 0)

        // When logging is enabled
        ImagePipeline.Configuration.isSignpostLoggingEnabled = true
        defer { ImagePipeline.Configuration.isSignpostLoggingEnabled = false }
        signpost(object, "Test", .begin, message())
        signpost(object, "Test", .end, message())

        // Then
        #expect(count == 2)
    }

    /// Measuring the work doesn't change it: it runs once, the value comes
    /// back, and so does the error.
    @Test(arguments: [false, true])
    func signpostedWorkReturnsItsResult(isEnabled: Bool) async {
        // Given
        ImagePipeline.Configuration.isSignpostLoggingEnabled = isEnabled
        defer { ImagePipeline.Configuration.isSignpostLoggingEnabled = false }
        let runs = OSAllocatedUnfairLock(initialState: 0)

        // Then
        #expect(signpost("Test") { runs.withLock { $0 += 1 }; return 42 } == 42)
        #expect(throws: MockError(description: "sync")) {
            try signpost("Test") { () throws -> Int in
                runs.withLock { $0 += 1 }
                throw MockError(description: "sync")
            }
        }
        let value = await signpost("Test") { @Sendable () async -> Int in
            await Task.yield()
            runs.withLock { $0 += 1 }
            return 7
        }
        #expect(value == 7)
        await #expect(throws: MockError(description: "async")) {
            try await signpost("Test") { @Sendable () async throws -> Int in
                await Task.yield()
                runs.withLock { $0 += 1 }
                throw MockError(description: "async")
            }
        }
        #expect(runs.withLock { $0 } == 4)
    }
}
