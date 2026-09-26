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

    /// The context of every container it was asked to encode, in order.
    var contexts: [ImageEncodingContext] { _contexts.withLock { $0 } }
    private let _contexts = OSAllocatedUnfairLock<[ImageEncodingContext]>(initialState: [])

    init(result: Data?) {
        self.result = result
    }

    func encode(_ image: PlatformImage) -> Data? {
        _encodeCount.withLock { $0 += 1 }
        return result
    }

    func encode(_ container: ImageContainer, context: ImageEncodingContext) -> Data? {
        _contexts.withLock { $0.append(context) }
        // The default implementation passes the data of a GIF through.
        if container.type == .gif {
            return container.data
        }
        return encode(container.image)
    }
}
