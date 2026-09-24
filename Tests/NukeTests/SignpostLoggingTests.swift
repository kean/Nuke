// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

/// The diagnostics send the signposts, so these run the common paths with
/// both on to make sure the signposted pipeline behaves exactly like the
/// plain one.
@Suite(.timeLimit(.minutes(5)))
struct SignpostLoggingTests {
    private let dataLoader: MockDataLoader
    private let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isDiagnosticsEnabled = true
            $0.signpostLog = OSLog(subsystem: "com.github.kean.Nuke.Tests", category: "Signposts")
        }
    }

    // MARK: Configuration

    @Test func signpostsAreOnByDefault() {
        #expect(ImagePipeline.Configuration().signpostLog === ImagePipeline.Diagnostics.defaultSignpostLog)
    }

    @Test func diagnosticsAreRecordedWithoutSignposts() async throws {
        // Given
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isDiagnosticsEnabled = true
            $0.signpostLog = nil
        }

        // When
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.image

        // Then
        #expect(task.metrics?.outcome == .success)
    }

    // MARK: Loading

    @Test func imageIsLoaded() async throws {
        // When
        let task = pipeline.imageTask(with: Test.request)
        let image = try await task.image

        // Then
        #expect(image.sizeInPixels == CGSize(width: 640, height: 480))
        #expect(task.metrics?.source == .network)
    }

    @Test func processedImageIsLoaded() async throws {
        // Given
        let request = ImageRequest(url: Test.url, processors: [
            .resize(size: CGSize(width: 320, height: 240), unit: .pixels)
        ])

        // When
        let image = try await pipeline.image(for: request)

        // Then
        #expect(image.sizeInPixels == CGSize(width: 320, height: 240))
    }

    @Test func failureIsLoaded() async {
        // Given
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))

        // Then
        await #expect(throws: ImagePipeline.Error.self) {
            try await pipeline.image(for: Test.request)
        }
    }

    /// Cancelling the task ends the intervals of the stages that were running.
    @Test func cancellationIsLogged() async throws {
        // Given
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

    /// Paused diagnostics send no signposts, and turning them back on in the
    /// middle of the load leaves no interval half-open.
    @Test func diagnosticsArePausedWhileLoadingImages() async {
        // Given
        let diagnostics = pipeline.diagnostics
        let writer = Task.detached {
            while !Task.isCancelled {
                diagnostics.isEnabled.toggle()
                await Task.yield()
            }
        }

        // When loading images while the switch is being toggled
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

    // MARK: Messages

    @Test func stageMessage() {
        // Given
        var download = ImagePipeline.Diagnostics.Stage(kind: .download, queuedAt: nil, startedAt: 0)
        download.source = .network
        download.bytes = 2048
        download.resumedBytes = 1024
        download.statusCode = 206

        var decode = ImagePipeline.Diagnostics.Stage(kind: .decode, queuedAt: nil, startedAt: 0)
        decode.isProgressive = true
        decode.decoder = "ImageDecoders.Default"
        decode.format = "jpeg"
        decode.pixels = .init(width: 640, height: 480)

        var lookup = ImagePipeline.Diagnostics.Stage(kind: .memoryLookup, queuedAt: nil, startedAt: 0)
        lookup.result = .miss

        // Then
        #expect(download.signpostMessage == "network · \(Formatter.bytes(2048)) · \(Formatter.bytes(1024)) resumed · HTTP 206")
        #expect(decode.signpostMessage == "preview · ImageDecoders.Default · jpeg · 640×480")
        #expect(lookup.signpostMessage == "miss")
        #expect(ImagePipeline.Diagnostics.Stage(kind: .rateLimit, queuedAt: nil, startedAt: 0).signpostMessage == "")
    }

    @Test func requestMessage() {
        #expect(ImageRequest(url: Test.url).signpostMessage == Test.url.absoluteString)
        let processed = ImageRequest(url: Test.url, processors: [.resize(width: 100)])
        #expect(processed.signpostMessage == "\(Test.url.absoluteString) · \(processed.processors[0].identifier)")
    }

    @Test func byteFormatter() {
        #expect(!Formatter.bytes(0).isEmpty)
        #expect(!Formatter.bytes(1024).isEmpty)
        #expect(Formatter.bytes(Int64(2048)) == Formatter.bytes(2048))
        // Zero is a number, not "Zero KB": the records print it next to other
        // byte counts
        #expect(Formatter.bytes(0).hasPrefix("0"), "\(Formatter.bytes(0))")
    }
}
