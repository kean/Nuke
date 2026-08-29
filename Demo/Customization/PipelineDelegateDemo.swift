// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI

/// Demonstrates ``ImagePipeline/Delegate-swift.protocol``: intercepting the
/// URL requests before they are sent and observing the pipeline events.
///
/// ```swift
/// let pipeline = ImagePipeline(delegate: DemoPipelineDelegate(log: log)) {
///     $0.imageCache = nil
/// }
/// ```
struct PipelineDelegateDemo: View {
    @StateObject private var model = PipelineDelegateDemoModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(model.photos, id: \.self) { url in
                    LazyImage(url: url) { state in
                        if let image = state.image {
                            image.resizable().scaledToFill()
                        } else {
                            DemoPlaceholder()
                        }
                    }
                    .pipeline(model.pipeline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 90)
                    .clipped()
                }
            }
            .id(model.reloadToken)

            PipelineEventLogView(log: model.log)
        }
        .toolbar {
            Button {
                model.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Pipeline Delegate",
        "`ImagePipeline.Delegate` customizes the pipeline per request. The one on this screen injects an HTTP header in `willLoadData` and records every event that the tasks produce.",
        code: """
        ImagePipeline(delegate: MyPipelineDelegate())
        """,
        points: [
            .init("Per request", "Every callback receives the `ImageRequest`, so the delegate can treat avatars differently from photos."),
            .init("willLoadData", "`willLoadData(for:urlRequest:pipeline:)` hands you the `URLRequest` before it is sent and takes back the one to use. It is async and throwing, so it can wait for a token to be refreshed, and throwing from it cancels the request."),
            .init("Events", "`imageTask(_:didReceiveEvent:pipeline:)` reports the progress, the previews, and the outcome of every task, which is what fills the log below."),
            .init("Caching", "The delegate also decides what is cached and under which key, including whether the original data is written to the disk cache."),
            .init("No caches here", "The demo disables them so that every reload actually goes to the network.")
        ]
    )
}

private struct PipelineEventLogView: View {
    @ObservedObject var log: PipelineEventLog

    var body: some View {
        List {
            Section {
                if log.events.isEmpty {
                    Text("No events yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(log.events) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.footnote.weight(.medium))
                        Text(event.subtitle)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Pipeline Events")
            }
        }
        .listStyle(.plain)
    }
}

@MainActor
private final class PipelineDelegateDemoModel: ObservableObject {
    let photos = Array(DemoImages.photos.prefix(4))
    let log = PipelineEventLog()
    let pipeline: ImagePipeline

    @Published private(set) var reloadToken = UUID()

    private let delegate: DemoPipelineDelegate

    init() {
        self.delegate = DemoPipelineDelegate(log: log)
        self.pipeline = ImagePipeline(delegate: delegate) {
            $0.imageCache = nil
            $0.dataLoader = DataLoader(configuration: {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.urlCache = nil
                return configuration
            }())
        }
    }

    func reload() {
        log.removeAll()
        reloadToken = UUID()
    }
}

/// A delegate that records what the pipeline is doing.
///
/// The reporting methods run on ``ImagePipelineActor``. The log is
/// `@MainActor`, which makes it `Sendable` and safe to capture here.
private final class DemoPipelineDelegate: ImagePipeline.Delegate {
    private let log: PipelineEventLog

    init(log: PipelineEventLog) {
        self.log = log
    }

    @ImagePipelineActor
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        var urlRequest = urlRequest
        // This is where an app injects an authorization token or signs the
        // request. Throwing from here cancels the request.
        urlRequest.setValue("nuke-demo", forHTTPHeaderField: "X-Nuke-Demo")
        record("willLoadData", name(for: request))
        return urlRequest
    }

    @ImagePipelineActor
    func imageTaskDidStart(_ task: ImageTask, pipeline: ImagePipeline) {
        record("imageTaskDidStart", name(for: task.request))
    }

    @ImagePipelineActor
    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        let name = name(for: task.request)
        switch event {
        case .progress(let progress):
            // Only the last one, to keep the log readable.
            guard progress.total > 0, progress.completed == progress.total else { return }
            record("didReceiveEvent(.progress)", "\(name) · \(demoByteCount(progress.total))")
        case .preview:
            record("didReceiveEvent(.preview)", name)
        case .finished(let result):
            switch result {
            case .success:
                record("didReceiveEvent(.finished)", "\(name) · success")
            case .failure(let error):
                record("didReceiveEvent(.finished)", "\(name) · \(error)")
            }
        }
    }

    private nonisolated func name(for request: ImageRequest) -> String {
        String((request.url?.lastPathComponent ?? "–").prefix(12))
    }

    private nonisolated func record(_ title: String, _ subtitle: String) {
        let log = log
        Task { @MainActor in
            log.append(title: title, subtitle: subtitle)
        }
    }
}

/// A log of the pipeline events. Being `@MainActor` makes it `Sendable`,
/// which is what lets the pipeline delegate write to it.
@MainActor
private final class PipelineEventLog: ObservableObject {
    struct Event: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
    }

    @Published private(set) var events: [Event] = []

    func append(title: String, subtitle: String) {
        events.insert(Event(title: title, subtitle: subtitle), at: 0)
        if events.count > 50 {
            events.removeLast(events.count - 50)
        }
    }

    func removeAll() {
        events.removeAll()
    }
}
