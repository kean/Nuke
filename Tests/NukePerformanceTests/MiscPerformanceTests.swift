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
}
