// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: a download cancelled after it received data records when the
// first byte arrived and the HTTP status, but not the bytes it received or the
// size the server announced, so the task has no `transfer:` field at all.
//
// Where: Sources/Nuke/Tasks/TaskFetchOriginalData.swift:261-272. The bytes,
// the source and the expected size are written only in `dataTaskDidFinish`,
// which returns early for a disposed job (`guard !isDisposed else { return }`)
// and is never reached on cancellation. `JobRecord.finish(.cancelled)` closes
// the stage (DiagnosticsRecorder.swift:261-271) without them.
//
// Expected (docs): `Stage.bytes` is "The bytes downloaded, read, or written";
// `Metrics.bytes` is "The bytes of the download the task waited on, if any";
// the header's transfer field is documented to say "what the server announced
// if the download stopped short of it". A download stopped by cancellation –
// the common way a download stops short – got 1/3 of the file and was told the
// full size.
//
// Actual: `firstByteAt` and `statusCode == 200` are set, `bytes`,
// `expectedBytes` and `source` are `nil`, and `metrics.bytes == nil`. A
// failure mid-download, by contrast, records `bytes` and `expectedBytes`.
@Suite(.timeLimit(.minutes(5)))
struct DiagnosticsCancelledDownloadDropsBytesRepro {
    @Test func cancelledDownloadKeepsTheBytesItReceived() async throws {
        // GIVEN a download that served its first chunk and holds the rest
        let dataLoader = MockProgressiveDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.dataCache = nil
            $0.isDiagnosticsEnabled = true
        }
        let task = pipeline.imageTask(with: Test.request)
        await waitUntil { task.status.progress.completed > 0 }
        let received = task.status.progress.completed

        // WHEN
        task.cancel()
        _ = try? await task.response

        // THEN (precondition) the download received data before it stopped
        let metrics = try #require(task.metrics)
        let download = try #require(metrics.jobs.last?.stages.first { $0.kind == .download })
        try #require(download.firstByteAt != nil)
        try #require(received > 0)

        // THEN the record says how much of it arrived, of how much
        #expect(download.bytes == received, "bytes \(String(describing: download.bytes)), \(received) received:\n\(metrics.description)")
        #expect(download.expectedBytes == Int64(dataLoader.data.count))
        #expect(metrics.bytes?.downloaded == received)
        #expect(metrics.description.contains("\ntransfer:"), "No transfer in:\n\(metrics.description)")
    }
}
