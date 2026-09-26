// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

/// A synchronous decoder that makes a preview of every chunk of data, unless
/// the previews are disabled or it's told to fail on the given chunks, and
/// counts the calls.
///
/// It isn't asynchronous, so the pipeline decodes on its actor as the data
/// arrives instead of dropping the chunks that arrive during a decode.
final class MockScriptedDecoder: ImageDecoding, @unchecked Sendable {
    let previewPolicy: ImagePipeline.PreviewPolicy
    private let failingPartialDecodes: Set<Int>
    private let _decode: (@Sendable (Data) throws -> ImageContainer)?
    private let image = Test.rgbImage(width: 4, height: 4)
    private let lock = NSLock()
    private var _partialDecodeCount = 0
    private var _finalDecodeCount = 0

    var partialDecodeCount: Int { lock.withLock { _partialDecodeCount } }
    var finalDecodeCount: Int { lock.withLock { _finalDecodeCount } }

    /// - parameters:
    ///   - previewPolicy: The partial decodes produce no previews when it's
    ///     `.disabled`.
    ///   - failingPartialDecodes: The one-based indices of the partial
    ///     decodes that produce no preview.
    ///   - decode: Decodes the final image, a 4 × 4 image by default.
    init(
        previewPolicy: ImagePipeline.PreviewPolicy = .incremental,
        failingPartialDecodes: Set<Int> = [],
        decode: (@Sendable (Data) throws -> ImageContainer)? = nil
    ) {
        self.previewPolicy = previewPolicy
        self.failingPartialDecodes = failingPartialDecodes
        self._decode = decode
    }

    convenience init(context: ImageDecodingContext) {
        self.init(previewPolicy: context.previewPolicy)
    }

    var isAsynchronous: Bool { false }

    func decode(_ data: Data) throws -> ImageContainer {
        lock.withLock { _finalDecodeCount += 1 }
        if let _decode {
            return try _decode(data)
        }
        return ImageContainer(image: image)
    }

    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        let index = lock.withLock {
            _partialDecodeCount += 1
            return _partialDecodeCount
        }
        guard previewPolicy != .disabled, !failingPartialDecodes.contains(index) else {
            return nil
        }
        return ImageContainer(image: image, isPreview: true)
    }
}
