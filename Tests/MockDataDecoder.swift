// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockFailingDecoder: Nuke.DataDecoding {
    var isFailing = false

    func decode(data: Data, response: URLResponse) -> Image? {
        return nil
    }
}
