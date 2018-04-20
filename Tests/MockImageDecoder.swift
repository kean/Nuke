// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockFailingDecoder: Nuke.ImageDecoding {
    func decode(data: Data, isFinal: Bool) -> Image? {
        return nil
    }
}

class MockImageDecoder: ImageDecoding {
    private let decoder = ImageDecoder()

    let name: String

    init(name: String) {
        self.name = name
    }

    func decode(data: Data, isFinal: Bool) -> Image? {
        return decoder.decode(data: data, isFinal: isFinal)
    }
}
