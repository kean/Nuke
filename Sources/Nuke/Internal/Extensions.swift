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
    var sha1: String {
        // Hashes the UTF-8 in place and writes the hex straight into the new
        // string: no `Data` copy of the key, no array behind the digest's
        // iterator, and no buffer to copy the hex out of. `withUTF8` only
        // copies a string that isn't contiguous UTF-8, e.g. a bridged one.
        var string = self
        var hasher = Insecure.SHA1()
        string.withUTF8 { hasher.update(bufferPointer: UnsafeRawBufferPointer($0)) }
        return hasher.finalize().withUnsafeBytes { digest in
            String(unsafeUninitializedCapacity: digest.count * 2) { buffer in
                var i = 0
                for byte in digest {
                    buffer[i] = sha1HexChars[Int(byte >> 4)]
                    buffer[i &+ 1] = sha1HexChars[Int(byte & 0x0F)]
                    i &+= 2
                }
                return i
            }
        }
    }
}

private let sha1HexChars: [UInt8] = Array("0123456789abcdef".utf8)

extension URL {
    var isLocalResource: Bool {
        // URI schemes are case-insensitive (RFC 3986).
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "file" || scheme == "data"
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
