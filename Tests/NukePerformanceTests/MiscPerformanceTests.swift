// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class MiscPerformanceTests: XCTestCase {
    /// Measures the overhead of spawning a large number of unstructured tasks
    /// on ``ImagePipelineActor`` using bare `Task { @ImagePipelineActor in }`.
    func testUnstructuredTasksOnActorPerformance() {
        let count = 100_000
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
    @available(iOS 17, *)
    func testDiscardingTaskGroupOnActorPerformance() {
        let count = 100_000
        measure {
            let group = DispatchGroup()
            group.enter()
            Task.detached {
                await withDiscardingTaskGroup {
                    for _ in 0..<count {
                        group.enter()
                        $0.addTask { @ImagePipelineActor in
                            group.leave()
                        }
                    }
                }
                group.leave()
            }
            group.wait()
        }
    }

    /// Measures the cost of generating SHA1-based cache filenames, which is on
    /// the hot path when ``DataCache`` resolves keys to filesystem entries.
    func testSHA1FilenameGenerationPerformance() {
        let count = 100_000
        let keys = (0..<count).map { "https://example.com/images/photo-\($0).jpg" }
        measure {
            for key in keys {
                _ = DataCache.filename(for: key)
            }
        }
    }
}
