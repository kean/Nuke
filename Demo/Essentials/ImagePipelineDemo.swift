// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import SwiftUI

/// Demonstrates the core ``ImagePipeline`` API: loading an image with
/// async/await, observing the download progress, and cancelling the task.
///
/// ```swift
/// let task = ImagePipeline.shared.imageTask(with: url)
/// for await progress in task.progress {
///     // Update progress
/// }
/// imageView.image = try await task.image
/// ```
struct ImagePipelineDemo: View {
    @StateObject private var model = ImagePipelineDemoModel()

    var body: some View {
        List {
            Section("Image") {
                imageView
                    .listRowInsets(EdgeInsets())
            }

            Section("Task") {
                LabeledContent("State", value: model.state.title)
                if model.state == .loading {
                    ProgressView(value: model.progress.fraction)
                    LabeledContent("Downloaded", value: "\(demoByteCount(model.progress.completed)) / \(demoByteCount(model.progress.total))")
                }
                if let response = model.response {
                    LabeledContent("Source", value: response.cacheType.map(description) ?? "Network")
                    LabeledContent("Size", value: "\(Int(response.image.size.width)) × \(Int(response.image.size.height)) px")
                    if let type = response.container.type {
                        LabeledContent("Format", value: type.rawValue)
                    }
                }
                if let duration = model.duration {
                    LabeledContent("Duration", value: String(format: "%.2f s", duration))
                }
                if let error = model.error {
                    Text(error.description)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("Load") { model.load() }
                    .disabled(model.state == .loading)
                Button("Cancel") { model.cancel() }
                    .disabled(model.state != .loading)
                Button("Reload Ignoring Caches") { model.load(options: [.reloadIgnoringCachedData]) }
                    .disabled(model.state == .loading)
            } footer: {
                Text("Load twice to see the image served from the memory cache. Cancelling frees the network and CPU resources immediately.")
            }
        }
        .onAppear { model.loadIfNeeded() }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Image Pipeline",
        "`ImagePipeline` downloads the image, decodes it, decompresses it in the background, and stores it in the caches. `ImageTask` reports the progress and can be cancelled at any point.",
        code: """
        let task = ImagePipeline.shared
            .imageTask(with: url)
        for await progress in task.progress {
            // Update the progress bar
        }
        let image = try await task.image
        """,
        points: [
            .init("Progress", "`task.progress` is an async sequence of the downloaded and the expected byte counts. It finishes when the image does."),
            .init("Cancellation", "Cancelling the Swift task cancels the download. The pipeline also cancels it when the last observer goes away."),
            .init("Source", "`ImageResponse.cacheType` says where the image came from: the memory cache, the disk cache, or the network."),
            .init("Reloading", "`.reloadIgnoringCachedData` skips every cache, which is how the demo forces a second download.")
        ]
    )

    @ViewBuilder private var imageView: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image = model.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(height: 240)
        .clipped()
    }

    private func description(_ cacheType: ImageResponse.CacheType) -> String {
        switch cacheType {
        case .memory: "Memory cache"
        case .disk: "Disk cache"
        }
    }
}

@MainActor
private final class ImagePipelineDemoModel: ObservableObject {
    enum State {
        case idle, loading, finished, cancelled, failed

        var title: String {
            switch self {
            case .idle: "Idle"
            case .loading: "Loading"
            case .finished: "Finished"
            case .cancelled: "Cancelled"
            case .failed: "Failed"
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var image: UIImage?
    @Published private(set) var progress = ImageTask.Progress(completed: 0, total: 0)
    @Published private(set) var response: ImageResponse?
    @Published private(set) var error: ImagePipeline.Error?
    @Published private(set) var duration: TimeInterval?

    private var task: ImageTask?
    private var observer: Task<Void, Never>?

    func loadIfNeeded() {
        guard state == .idle else { return }
        load()
    }

    func load(options: ImageRequest.Options = []) {
        cancel()

        image = nil
        response = nil
        error = nil
        duration = nil
        progress = ImageTask.Progress(completed: 0, total: 0)
        state = .loading

        let startTime = Date()
        let request = ImageRequest(url: DemoImages.landscape, options: options)

        // The task starts executing the moment it is created.
        let task = ImagePipeline.shared.imageTask(with: request)
        self.task = task

        // A single stream delivers the progress, the progressive previews,
        // and the final result.
        observer = Task { [weak self] in
            for await event in task.events {
                guard let self else { return }
                switch event {
                case .progress(let progress):
                    self.progress = progress
                case .preview(let response):
                    self.image = response.image
                case .finished(let result):
                    self.duration = Date().timeIntervalSince(startTime)
                    switch result {
                    case .success(let response):
                        self.image = response.image
                        self.response = response
                        self.state = .finished
                    case .failure(let error):
                        self.error = error
                        if case .cancelled = error {
                            self.state = .cancelled
                        } else {
                            self.state = .failed
                        }
                    }
                }
            }
        }
    }

    func cancel() {
        observer?.cancel()
        observer = nil
        task?.cancel()
        task = nil
    }
}
