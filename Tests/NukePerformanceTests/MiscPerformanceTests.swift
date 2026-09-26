// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Nuke

@Suite(.serialized)
@MainActor
struct MiscPerformanceTests {
    /// Measures the cost of generating SHA1-based cache filenames, which is on
    /// the hot path when ``DataCache`` resolves keys to filesystem entries.
    @Test
    func sha1FilenameGeneration() {
        let count = 100_000
        let keys = (0..<count).map { "https://example.com/images/photo-\($0).jpg" }
        measure {
            for key in keys {
                _ = DataCache.filename(for: key)
            }
        }
    }
}
