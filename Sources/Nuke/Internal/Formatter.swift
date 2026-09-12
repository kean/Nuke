// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

enum Formatter {
    static func bytes(_ count: Int) -> String {
        bytes(Int64(count))
    }

    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowsNonnumericFormatting = false // "0 bytes", not "Zero KB"
        return formatter.string(fromByteCount: count)
    }

    /// A duration in milliseconds, never rounded to a `0.0 ms` that isn't true.
    static func milliseconds(_ duration: TimeInterval) -> String {
        let milliseconds = duration * 1000
        guard milliseconds >= 0.05 else { return "<0.1 ms" }
        return String(format: "%.1f ms", milliseconds)
    }
}
