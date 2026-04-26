// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import CryptoKit

extension String {
    /// Calculates SHA1 from the given string and returns its hex representation.
    ///
    /// ```swift
    /// print("http://test.com".sha1)
    /// // prints "50334ee0b51600df6397ce93ceed4728c37fee4e"
    /// ```
    var sha1: String? {
        guard let input = self.data(using: .utf8) else {
            return nil // The conversion to .utf8 should never fail
        }
        let digest = Insecure.SHA1.hash(data: input)
        let hexCount = Insecure.SHA1Digest.byteCount * 2
        let bytes = [UInt8](unsafeUninitializedCapacity: hexCount) { buffer, count in
            var i = 0
            for byte in digest {
                buffer[i] = sha1HexChars[Int(byte >> 4)]
                buffer[i &+ 1] = sha1HexChars[Int(byte & 0x0F)]
                i &+= 2
            }
            count = hexCount
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

private let sha1HexChars: [UInt8] = Array("0123456789abcdef".utf8)

extension URL {
    var isLocalResource: Bool {
        scheme == "file" || scheme == "data"
    }
}

extension ImageRequest.Priority {
    var taskPriority: TaskPriority {
        switch self {
        case .veryLow: return .veryLow
        case .low: return .low
        case .normal: return .normal
        case .high: return .high
        case .veryHigh: return .veryHigh
        }
    }
}

struct AnonymousCancellable: Cancellable {
    let onCancel: @Sendable () -> Void

    func cancel() {
        onCancel()
    }
}

@concurrent func performInBackground<T>(_ closure: @Sendable () -> T) async -> T {
    closure()
}
