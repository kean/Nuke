// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Nuke

@Suite
struct MiscPerformanceTests {
    /// Measures the overhead of spawning a large number of unstructured tasks
    /// on ``ImagePipelineActor`` using bare `Task { @ImagePipelineActor in }`.
    @Test
    func unstructuredTasksOnActor() {
        let count = 50_000
        measure {
            let group = DispatchGroup()
            for _ in 0..<count {
                group.enter()
                Task { @ImagePipelineActor in
                    group.leave()
                }
            }
            group.wait()
        }
    }

    /// Measures the same workload using `withDiscardingTaskGroup`, which avoids
    /// accumulating child-task results and may reduce allocations at scale.
    @Test
    @available(iOS 17, *)
    func discardingTaskGroupOnActor() async {
        let count = 50_000
        await measure {
            await withDiscardingTaskGroup {
                for _ in 0..<count {
                    $0.addTask { @ImagePipelineActor in }
                }
            }
        }
    }

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
