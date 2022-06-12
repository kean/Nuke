// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockFailingDecoder: Nuke.ImageDecoding {
    func decode(_ data: Data) throws -> ImageContainer {
        throw ImageDecodingError.unknown
    }
}

class MockImageDecoder: ImageDecoding {
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

class MockAnonymousImageDecoder: ImageDecoding {
    let closure: (Data, Bool) -> PlatformImage?

    init(_ closure: @escaping (Data, Bool) -> PlatformImage?) {
        self.closure = closure
    }

    func decode(_ data: Data) throws -> ImageContainer {
        guard let image = closure(data, true) else {
            throw ImageDecodingError.unknown
        }
        return ImageContainer(image: image)
    }

    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        closure(data, false).map { ImageContainer(image: $0) }
    }
}
