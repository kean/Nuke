// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

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

class MockAnonymousImageDecoder: ImageDecoding {
    let closure: (Data, Bool) -> Image?

    init(_ closure: @escaping (Data, Bool) -> Image?) {
        self.closure = closure
    }

    func decode(data: Data, isFinal: Bool) -> Image? {
        return closure(data, isFinal)
    }
}
