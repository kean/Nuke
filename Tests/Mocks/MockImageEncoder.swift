// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os
import Nuke

final class MockImageEncoder: ImageEncoding {
    let result: Data?

    // The pipeline encodes in the background.
    var encodeCount: Int { _encodeCount.withLock { $0 } }
    private let _encodeCount = OSAllocatedUnfairLock(initialState: 0)

    init(result: Data?) {
        self.result = result
    }

    func encode(_ image: PlatformImage) -> Data? {
        _encodeCount.withLock { $0 += 1 }
        return result
    }
}
