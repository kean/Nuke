// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// The signposts that the diagnostics send: the log they go to, and the
/// messages their intervals carry. The other diagnostics tests keep the
/// default `signpostLog`, so every one of them runs the signposted pipeline.
@Suite(.timeLimit(.minutes(5)))
struct DiagnosticsSignpostsTests {
    // MARK: Configuration

    @Test func signpostsAreOnByDefault() {
        #expect(ImagePipeline.Configuration().signpostLog === ImagePipeline.Diagnostics.defaultSignpostLog)
    }

    @Test func diagnosticsAreRecordedWithoutSignposts() async throws {
        // Given
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
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
        // Zero is a number, not "Zero KB": the records print it next to other
        // byte counts
        #expect(Formatter.bytes(0).hasPrefix("0"), "\(Formatter.bytes(0))")
    }
}
