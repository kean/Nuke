// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

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
        var output = ""
        for byte in digest {
            output.append(String(format: "%02x", byte))
        }
        return output
    }
}

extension URL {
    var isLocalResource: Bool {
        let scheme = self.scheme
        return scheme == "file" || scheme == "data"
    }
}

// TODO: remove
func performInBackground<T>(_ closure: @Sendable () -> T) async -> T {
    closure()
}
