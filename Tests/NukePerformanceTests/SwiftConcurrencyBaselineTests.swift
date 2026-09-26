// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Nuke

/// Baselines for the Swift concurrency runtime the pipeline runs on, not
/// benchmarks of Nuke: no Nuke code runs in them. They time starting tasks on
/// ``ImagePipelineActor``, which every image task does, so read the pipeline
/// numbers against them.
@Suite(.serialized)
@MainActor
struct SwiftConcurrencyBaselineTests {
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
}
