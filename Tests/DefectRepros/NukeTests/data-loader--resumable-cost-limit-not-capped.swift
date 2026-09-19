// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: the resumable data storage isn't capped at 32 MB as documented.
//
// Sources/Nuke/Internal/ResumableData.swift:
//
//     /// Cost limit for resumable data: 1% of physical memory, capped at 32 MB.
//     static var defaultCostLimit: Int {
//         Int(Double(ProcessInfo.processInfo.physicalMemory) * 0.01)
//     }
//
// There is no cap: the limit is 1% of RAM on every device, e.g. ~80 MB on an
// 8 GB iPhone and ~687 MB on a 64 GB Mac, all of it partial downloads held in
// memory. Before f0f07cc0 ("Make ResumableData limit dynamic") the limit was a
// fixed 32 MB; the commit kept the cap in the comment but not in the code.
// (`Cache` also drops single entries above 10% of the limit, so the largest
// resumable entry grows the same way.)
//
// Expected: `defaultCostLimit` <= 32 MB on any machine.
// Actual:   `defaultCostLimit` == 1% of physical memory (fails on any machine
//           with more than ~3.2 GB of RAM).

@ImagePipelineActor
@Suite(.timeLimit(.minutes(1)))
struct ResumableDataCostLimitCapBugTests {
    @Test func defaultCostLimitIsCappedAt32MB() {
        let limit = ResumableDataStorage.defaultCostLimit
        #expect(limit > 0)
        #expect(limit <= 32 * 1024 * 1024, "\(limit) bytes with \(ProcessInfo.processInfo.physicalMemory) bytes of RAM")
    }
}
