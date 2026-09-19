// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: when `ImagePipeline.Delegate.willLoadData(for:urlRequest:pipeline:)`
// throws, the download never starts, yet its stage is stamped as a network
// download of zero bytes, and the task reports a transfer.
//
// Where: Sources/Nuke/Tasks/TaskFetchOriginalData.swift:264 (`dataTaskDidFinish`):
//
//     diagnostics?.endStage(downloadStage) { stage in
//         stage.source = stage.urlSessionMetrics?.isServedFromCache == true ? .httpCache : .network
//         stage.bytes = Int64(data.count)
//         stage.resumedBytes = resumedDataCount
//         ...
//
// runs for every failure, including the one thrown by the delegate before
// `diagnostics?.startStage(downloadStage)` was ever reached. The stage keeps
// `startedAt == nil` (it prints "never started"), but gets `source = .network`
// and `bytes = 0`, and `TaskRecord.bytes(of:)` then copies `bytes: 0` up into
// `ImageTask.Metrics.bytes`.
//
// Expected: `Stage.source` is "Where a download got the data from" and
// `Metrics.bytes` is "The bytes of the download the task waited on, if any" –
// a download that never started got nothing from anywhere, so both are `nil`
// and the header has no `transfer:` field.
//
// Actual:
//     transfer:  0 bytes
//     ...
//     ├─ download   0.2 ms  █████████  44%  never started · network · 0 bytes
@Suite(.timeLimit(.minutes(5)))
struct DiagnosticsNeverStartedDownloadTransferRepro {
    @Test func downloadTheDelegateRefusedReportsNoTransfer() async throws {
        // GIVEN a delegate that refuses to load the data
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline(delegate: _RefusingDelegate()) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isDiagnosticsEnabled = true
        }

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try? await task.response

        // THEN (precondition) the download never started
        let metrics = try #require(task.metrics)
        let download = try #require(metrics.jobs.last?.stages.first { $0.kind == .download })
        try #require(download.startedAt == nil)
        try #require(dataLoader.createdTaskCount == 0)

        // THEN it has no source and no bytes, and the task no transfer
        #expect(download.source == nil, "A download that never started reports source \(String(describing: download.source))")
        #expect(download.bytes == nil, "A download that never started reports \(String(describing: download.bytes)) bytes")
        #expect(metrics.bytes == nil, "The task reports a transfer: \(String(describing: metrics.bytes))")
        #expect(!metrics.description.contains("\ntransfer:"), "Unexpected transfer in:\n\(metrics.description)")
    }
}

private final class _RefusingDelegate: ImagePipeline.Delegate, Sendable {
    @ImagePipelineActor
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        throw URLError(.userAuthenticationRequired)
    }
}
