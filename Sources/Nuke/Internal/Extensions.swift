// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import CryptoKit

extension String {
    /// Calculates SHA256 from the given string and returns its hex representation.
    ///
    /// ```swift
    /// print("http://test.com".sha256)
    /// // prints "8b408a0c7163fdfff06ced3e80d7d2b3acd9db900905c4783c28295b8c996165"
    /// ```
    var sha256: String? {
        guard let input = self.data(using: .utf8) else {
            return nil // The conversion to .utf8 should never fail
        }
        let digest = CryptoKit.SHA256.hash(data: input)
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
