// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

final class MockImageEncoder: ImageEncoding {
    let result: Data?
    var encodeCount = 0

    init(result: Data?) {
        self.result = result
    }

    func encode(_ image: PlatformImage) -> Data? {
        encodeCount += 1
        return result
    }
}
