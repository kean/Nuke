// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import os

extension DemoPipelineProbe {
    /// One pipeline's figures behind a lock, and the bookkeeping behind them.
    ///
    /// It is an object of its own, rather than state on the probe, so that the
    /// registry can keep the counts of a pipeline that is gone.
    ///
    /// Every method takes the lock once and doesn't allocate on the way, apart
    /// from the dictionaries growing, so it is cheap enough for the pipeline's
    /// busiest paths.
    final class Counters: Sendable {
        private let state: OSAllocatedUnfairLock<State>

        init(label: String) {
            var figures = DemoPipelineDiagnostics()
            figures.label = label
            figures.pipelineCount = 1
            state = OSAllocatedUnfairLock(initialState: State(figures: figures))
        }

        /// A copy of the figures.
        var figures: DemoPipelineDiagnostics {
            state.withLock { $0.figures }
        }

        /// Starts the figures over. What is running now stays counted as
        /// running, and is counted when it ends.
        func reset() {
            state.withLock { state in
                let old = state.figures
                var new = DemoPipelineDiagnostics()
                new.label = old.label
                new.pipelineCount = old.pipelineCount
                new.activeTaskCount = old.activeTaskCount
                new.peakActiveTaskCount = old.activeTaskCount
                new.decompressingQueue = old.decompressingQueue
                state.figures = new
            }
        }

        // MARK: Tasks

        func taskCreated(_ task: ImageTask) {
            let id = task.id
            let now = ContinuousClock.now
            state.withLock { state in
                state.taskCreatedAt[id] = now
                state.figures.createdTaskCount += 1
                state.figures.activeTaskCount += 1
                state.figures.peakActiveTaskCount = max(state.figures.peakActiveTaskCount, state.figures.activeTaskCount)
            }
        }

        func taskFinished(_ task: ImageTask, with result: Result<ImageResponse, ImagePipeline.Error>) {
            let id = task.id
            let now = ContinuousClock.now
            let outcome = TaskOutcome(result)
            state.withLock { state in
                // A task created before the probe was attached was never counted in.
                guard let createdAt = state.taskCreatedAt.removeValue(forKey: id) else { return }
                state.figures.activeTaskCount -= 1
                switch outcome {
                case .image(let cacheType):
                    state.figures.succeededTaskCount += 1
                    state.figures.taskDuration.record((now - createdAt).seconds, at: now)
                    switch cacheType {
                    case .memory?: state.figures.memoryResponseCount += 1
                    case .disk?: state.figures.diskResponseCount += 1
                    case nil: state.figures.networkResponseCount += 1
                    }
                case .cancelled:
                    state.figures.cancelledTaskCount += 1
                case .failed(let reason):
                    state.figures.failedTaskCount += 1
                    state.figures.failureCounts[reason, default: 0] += 1
                }
            }
        }

        // MARK: Disk Cache

        func diskWrite(byteCount: Int, isEncodedImage: Bool) {
            state.withLock { state in
                state.figures.diskWriteCount += 1
                state.figures.diskWriteByteCount += Int64(byteCount)
                if isEncodedImage {
                    state.figures.encodedImageWriteCount += 1
                }
            }
        }

        // MARK: Downloads

        func downloadRequested() {
            state.withLock { $0.figures.downloadCount += 1 }
        }

        // MARK: Decompression

        func decompressionStarted() {
            state.withLock { $0.figures.decompressingQueue.inFlightCount? += 1 }
        }

        func decompressionFinished(startedAt: ContinuousClock.Instant) {
            let now = ContinuousClock.now
            state.withLock { state in
                state.figures.decompressingQueue.inFlightCount? -= 1
                state.figures.decompression.record((now - startedAt).seconds, at: now)
            }
        }

        func decompressionDeclined() {
            state.withLock { $0.figures.declinedDecompressionCount += 1 }
        }
    }
}

// MARK: - State

extension DemoPipelineProbe.Counters {
    private struct State: Sendable {
        var figures: DemoPipelineDiagnostics
        /// The tasks created and not yet finished.
        var taskCreatedAt: [ObjectIdentifier: ContinuousClock.Instant] = [:]
    }

    private enum TaskOutcome: Sendable {
        case image(ImageResponse.CacheType?)
        case cancelled
        case failed(String)

        init(_ result: Result<ImageResponse, ImagePipeline.Error>) {
            switch result {
            case .success(let response):
                self = .image(response.cacheType)
            case .failure(.cancelled):
                self = .cancelled
            case .failure(let error):
                self = .failed(error.caseName)
            }
        }
    }
}

extension ImagePipeline.Error {
    /// The name of the case, without its payload, to group failures by.
    fileprivate var caseName: String {
        switch self {
        case .dataMissingInCache: "dataMissingInCache"
        case .dataLoadingFailed: "dataLoadingFailed"
        case .dataIsEmpty: "dataIsEmpty"
        case .decoderNotRegistered: "decoderNotRegistered"
        case .decodingFailed: "decodingFailed"
        case .processingFailed: "processingFailed"
        case .imageRequestMissing: "imageRequestMissing"
        case .pipelineInvalidated: "pipelineInvalidated"
        case .dataDownloadExceededMaximumSize: "dataDownloadExceededMaximumSize"
        case .cancelled: "cancelled"
        @unknown default: "unknown"
        }
    }
}

extension Duration {
    /// In seconds, the unit of every duration in ``DemoPipelineDiagnostics``.
    fileprivate var seconds: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
