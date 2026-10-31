// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Performance/performance-guide.md`.

import Foundation
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

// Snippets from `Documentation/Nuke.docc/Essentials/troubleshooting.md`.

private func troubleshooting(pipeline: ImagePipeline, url: URL) async throws {
    print(await ImagePipeline.shared.diagnostics.snapshot())

    let task = pipeline.imageTask(with: url)
    _ = try await task.image
    print(task.metrics!)
}

private final class Telemetry: Sendable {}

extension Telemetry: ImagePipeline.Delegate {
    @ImagePipelineActor
    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        guard case .finished = event, let metrics = task.metrics else { return }
        send(metrics) // Encode it with JSONEncoder, or print it
    }

    nonisolated func send(_ metrics: ImageTask.Metrics) {}
}

private func upload(_ data: Data) {}

private func send(_ metrics: ImageTask.Metrics) throws {
    let record = try JSONSerialization.jsonObject(with: JSONEncoder().encode(metrics))
    upload(try JSONSerialization.data(withJSONObject: removingQueries(from: record)))
}

/// Cuts every URL in an encoded record at its query, and drops the server's address.
private func removingQueries(from value: Any) -> Any {
    switch value {
    case let string as String where string.contains("://"):
        String(string.prefix { $0 != "?" && $0 != "#" })
    case let array as [Any]:
        array.map(removingQueries)
    case let object as [String: Any]:
        object.filter { $0.key != "remoteAddress" }.mapValues(removingQueries)
    default:
        value
    }
}

private func diagnosticsWithoutSignposts() {
    let pipeline = ImagePipeline {
        $0.isDiagnosticsEnabled = true
        $0.signpostLog = nil
    }
    _ = pipeline
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
