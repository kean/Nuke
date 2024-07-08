// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

public final class MockImageEncoder: ImageEncoding, @unchecked Sendable {
    public let result: Data?
    public var encodeCount = 0

    public init(result: Data?) {
        self.result = result
    }

    public func encode(_ image: PlatformImage) -> Data? {
        encodeCount += 1
        return result
    }
}
