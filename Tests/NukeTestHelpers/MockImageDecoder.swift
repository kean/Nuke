// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

public class MockFailingDecoder: Nuke.ImageDecoding, @unchecked Sendable {
    public init() {}

    public func decode(_ data: Data) throws -> ImageContainer {
        throw MockError(description: "decoder-failed")
    }
}

public final class MockImageDecoder: ImageDecoding, @unchecked Sendable {
    private let decoder = ImageDecoders.Default()

    public let name: String

    public init(name: String) {
        self.name = name
    }

    public func decode(_ data: Data) throws -> ImageContainer {
        try decoder.decode(data)
    }

    public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        decoder.decodePartiallyDownloadedData(data)
    }
}

public class MockAnonymousImageDecoder: ImageDecoding, @unchecked Sendable {
    let closure: (Data, Bool) -> PlatformImage?

    public init(_ closure: @escaping (Data, Bool) -> PlatformImage?) {
        self.closure = closure
    }

    public convenience init(output: PlatformImage) {
        self.init { _, _ in output }
    }

    public func decode(_ data: Data) throws -> ImageContainer {
        guard let image = closure(data, true) else {
            throw ImageDecodingError.unknown
        }
        return ImageContainer(image: image)
    }

    public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        closure(data, false).map { ImageContainer(image: $0) }
    }
}
