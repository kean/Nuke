// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
@testable import Nuke

public final class MockImageCache: ImageCaching, @unchecked Sendable {
    public let queue = DispatchQueue(label: "com.github.Nuke.MockCache")
    public var enabled = true
    public var images = [AnyHashable: ImageContainer]()
    public var readCount = 0
    public var writeCount = 0

    public init() {}

    public func resetCounters() {
        readCount = 0
        writeCount = 0
    }

    public subscript(key: ImageCacheKey) -> ImageContainer? {
        get {
            queue.sync {
                readCount += 1
                return enabled ? images[key] : nil
            }
        }
        set {
            queue.sync {
                writeCount += 1
                if let image = newValue {
                    if enabled { images[key] = image }
                } else {
                    images[key] = nil
                }
            }
        }
    }

    public func removeAll() {
        images.removeAll()
    }
}
