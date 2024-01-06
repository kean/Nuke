// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

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
        scheme == "file" || scheme == "data"
    }
}

extension OperationQueue {
    convenience init(maxConcurrentCount: Int) {
        self.init()
        self.maxConcurrentOperationCount = maxConcurrentCount
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

final class AnonymousCancellable: Cancellable {
    let onCancel: @Sendable () -> Void

    init(_ onCancel: @Sendable @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel()
    }
}
