// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Performance/performance-guide.md`.

import Foundation
import os
import Nuke

private func aggressiveDiskCache() {
    var configuration = ImagePipeline.Configuration.withDataCache()
    configuration.dataCachePolicy = .automatic

    ImagePipeline.shared = ImagePipeline(configuration: configuration)
}

private func downsampleImages() {
    let url = URL(string: "https://example.com/image")!
    // Target size is in points
    let request = ImageRequest(url: url, processors: [.resize(width: 320)])
    _ = request
}

private func coalescing(pipeline: ImagePipeline) {
    let url = URL(string: "https://example.com/image")

    // Only one network request is made for both of these
    let blurred = pipeline.imageTask(with: ImageRequest(url: url, processors: [
        .resize(size: CGSize(width: 44, height: 44)),
        .gaussianBlur(radius: 8)
    ]))
    let thumbnail = pipeline.imageTask(with: ImageRequest(url: url, processors: [
        .resize(size: CGSize(width: 44, height: 44))
    ]))
    _ = (blurred, thumbnail)
}

private func diagnostics(url: URL) async throws {
    let pipeline = ImagePipeline {
        $0.isDiagnosticsEnabled = true
    }

    let task = pipeline.imageTask(with: url)
    let image = try await task.image
    print(task.metrics!)
    _ = image
}

private final class Telemetry: ImagePipeline.Delegate, Sendable {
    @ImagePipelineActor
    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        guard case .finished = event, let metrics = task.metrics else { return }
        send(metrics) // Encode it with JSONEncoder, or print it
    }

    nonisolated func send(_ metrics: ImageTask.Metrics) {}
}

private let signposter = OSSignposter(subsystem: "com.example.app", category: "Images")

private final class ImageSignposts: ImagePipeline.Delegate, Sendable {
    @ImagePipelineActor private var intervals: [ImageTask.ID: OSSignpostIntervalState] = [:]

    @ImagePipelineActor
    func imageTaskDidStart(_ task: ImageTask, pipeline: ImagePipeline) {
        intervals[task.id] = signposter.beginInterval("LoadImage", id: signposter.makeSignpostID())
    }

    @ImagePipelineActor
    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        guard case .finished = event, let interval = intervals.removeValue(forKey: task.id) else { return }
        signposter.endInterval("LoadImage", interval)
    }
}

private func progressiveDecoding() {
    ImagePipeline.shared = ImagePipeline {
        $0.isProgressiveDecodingEnabled = true
    }
}

#if canImport(UIKit) && !os(watchOS)

import UIKit

private final class ImageView: UIView {
    private var task: ImageTask?

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)

        task?.priority = newWindow == nil ? .low : .high
    }
}

#endif
