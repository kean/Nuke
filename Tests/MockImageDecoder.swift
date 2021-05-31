// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockFailingDecoder: Nuke.ImageDecoding {
    func decode(_ data: Data) -> ImageContainer? {
        return nil
    }
}

class MockImageDecoder: ImageDecoding {
    private let decoder = ImageDecoders.Default()

    let name: String

    init(name: String) {
        self.name = name
    }

    func decode(_ data: Data) -> ImageContainer? {
        return decoder.decode(data)
    }

    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        return decoder.decodePartiallyDownloadedData(data)
    }
}

class MockAnonymousImageDecoder: ImageDecoding {
    let closure: (Data, Bool) -> PlatformImage?

    init(_ closure: @escaping (Data, Bool) -> PlatformImage?) {
        self.closure = closure
    }

    func decode(_ data: Data) -> ImageContainer? {
        return closure(data, true).map { ImageContainer(image: $0) }
    }

    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        return closure(data, false).map { ImageContainer(image: $0) }
    }
}
