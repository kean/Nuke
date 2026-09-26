// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockFailingDecoder: Nuke.ImageDecoding, @unchecked Sendable {
    func decode(_ data: Data) throws -> ImageContainer {
        throw MockError(description: "decoder-failed")
    }
}

class MockImageDecoder: ImageDecoding, @unchecked Sendable {
    private let decoder = ImageDecoders.Default()

    let name: String

    init(name: String) {
        self.name = name
    }

    func decode(_ data: Data) throws -> ImageContainer {
        try decoder.decode(data)
    }

    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        decoder.decodePartiallyDownloadedData(data)
    }
}
