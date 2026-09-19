// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG (docs vs. behavior, macOS only): setting
// `ImagePipeline.Configuration.isDecompressionEnabled` to `true` on macOS has no
// effect.
//
// Expected: the option is documented as "Decompresses the loaded images. By
// default, enabled on all platforms except for `macOS`", which reads as an
// opt-in on macOS. `ImagePipeline.Delegate.shouldDecompress(response:for:pipeline:)`
// and `decompress(response:request:pipeline:)` are public hooks that, with the
// option on, should be consulted for the loaded images.
//
// Actual: `TaskLoadImage` only decompresses the images marked as needing it,
// and the only place that marks them – `makeImageResponse` in
// ImageDecoding.swift – is compiled out on macOS (`#if !os(macOS)`). The option
// is read, but never reached: neither delegate hook is ever called on macOS,
// and `ImageDecompression.decompress` (which works on macOS) never runs.
//
// Sources/Nuke/Decoding/ImageDecoding.swift:105
#if os(macOS)
@Suite(.timeLimit(.minutes(5)))
struct MacOSDecompressionOptInBugRepro {
    @Test func enablingDecompressionOnMacOSDecompressesTheLoadedImages() async throws {
        // GIVEN decompression enabled explicitly
        let delegate = RecordingDecompressionDelegate()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
            $0.isDecompressionEnabled = true
        }

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN the image is decompressed
        #expect(delegate.shouldDecompressCount == 1) // Actual: 0
        #expect(delegate.decompressCount == 1)       // Actual: 0
    }
}

private final class RecordingDecompressionDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _shouldDecompressCount = 0
    private var _decompressCount = 0

    var shouldDecompressCount: Int { lock.withLock { _shouldDecompressCount } }
    var decompressCount: Int { lock.withLock { _decompressCount } }

    func shouldDecompress(response: ImageResponse, for request: ImageRequest, pipeline: ImagePipeline) -> Bool {
        lock.withLock { _shouldDecompressCount += 1 }
        return pipeline.configuration.isDecompressionEnabled
    }

    func decompress(response: ImageResponse, request: ImageRequest, pipeline: ImagePipeline) -> ImageResponse {
        lock.withLock { _decompressCount += 1 }
        var response = response
        response.container.image = ImageDecompression.decompress(image: response.image)
        return response
    }
}
#endif
