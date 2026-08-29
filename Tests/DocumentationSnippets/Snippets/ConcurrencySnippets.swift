// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Customization/where-work-runs.md`.

import Foundation
import Nuke

// MARK: - ImagePipelineActor

@ImagePipelineActor
private final class RequestLog {
    private var started: [ImageTask.ID: Date] = [:]

    func record(_ task: ImageTask) {
        started[task.id] = Date() // No lock needed: the actor serializes access
    }
}

// MARK: - The Task Queues

private func customQueueLimits() {
    let pipeline = ImagePipeline {
        $0.imageProcessingQueue.maxConcurrentTaskCount = 4
    }
    _ = pipeline
}

// MARK: - Delegate Isolation

@MainActor
private final class PipelineObserver: ImagePipeline.Delegate {
    var inFlight = 0

    nonisolated func imageTaskCreated(_ task: ImageTask, pipeline: ImagePipeline) {
        Task { @MainActor in self.inFlight += 1 }
    }
}
