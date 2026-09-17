// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import SwiftUI

/// Demonstrates the core ``ImagePipeline`` API: loading an image with
/// async/await, observing the download progress, and cancelling the task,
/// then the same bytes with ``ImagePipeline/data(for:)`` and no decoding.
///
/// ```swift
/// let task = ImagePipeline.shared.imageTask(with: url)
/// for await progress in task.progress {
///     // Update progress
/// }
/// imageView.image = try await task.image
///
/// let (data, response) = try await ImagePipeline.shared.data(for: request)
/// ```
///
/// The photo is the HEIC one rather than the landscape photo Getting Started
/// loads through the same pipeline: on an iPad, Getting Started runs from
/// launch, and the first Load here would find its image in the memory cache
/// and show no download at all.
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
                    LabeledContent("Source", value: Self.source(of: response))
                    LabeledContent("Size", value: "\(Int(response.image.size.width)) × \(Int(response.image.size.height)) px")
                    if let type = response.container.type {
                        LabeledContent("Format", value: type.rawValue)
                    }
                }
                if let duration = model.duration {
                    LabeledContent("Duration", value: String(format: "%.2f s", duration))
                }
                if let error = model.error, !error.isCancelled {
                    ErrorRow(error: error)
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

            Section {
                Button("Load Data") { model.loadData() }
                    .disabled(model.isLoadingData)
                if model.isLoadingData {
                    LabeledContent("State", value: "Loading")
                }
                if let data = model.data {
                    LabeledContent("Data", value: data.summary)
                    LabeledContent("Source", value: data.source)
                    LabeledContent("Duration", value: String(format: "%.2f s", data.duration))
                }
                if let error = model.dataError, !error.isCancelled {
                    ErrorRow(error: error)
                }
            } header: {
                Text("Data")
            } footer: {
                Text("`data(for:)` returns the same image's bytes and its `URLResponse` with nothing decoded, for a file to save or share. It doesn't look in the memory cache, which holds images, not data, and it reads the disk cache first on a pipeline that has one; this one leaves its data to `URLCache`.")
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

        // The bytes alone
        let pipeline = ImagePipeline.shared
        let (data, response) = try await pipeline
            .data(for: ImageRequest(url: url))
        """,
        points: [
            .init("Progress", "`task.progress` is an async sequence of the downloaded and the expected byte counts. It finishes when the image does."),
            .init("Cancellation", "Cancelling the Swift task cancels the download. The pipeline also cancels it when the last observer goes away."),
            .init("Source", "`ImageResponse.cacheType` says where the image came from: the memory cache, the disk cache, or `nil` for the data loader. The shared pipeline keeps its data in `URLCache`, which answers inside the loader, so `nil` can be a download or a cached response alike."),
            .init("Reloading", "`.reloadIgnoringCachedData` skips the pipeline's caches, which is how the demo decodes the image again. `URLCache` may still answer the download."),
            .init("Data only", "`data(for:)` loads the bytes and stops: no decoding, no processing, nothing in the memory cache. It is the call for saving an image to a file or handing it to a share sheet. A download of the same URL that is already running is shared, as it is between image tasks."),
            .init("Errors", "A failed download is `ImagePipeline.Error.dataLoadingFailed`, and the error the data loader reported is its `dataLoadingError`: a `URLError`, or `DataLoader.Error.statusCodeUnacceptable` for a status outside 200–299.")
        ]
    )

    @ViewBuilder private var imageView: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image = model.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if model.state == .failed {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 240)
        .clipped()
    }

    private static func source(of response: ImageResponse) -> String {
        switch response.cacheType {
        case .memory: "Memory cache"
        case .disk: "Disk cache"
        case nil: DemoFixture.isFixture(response.request.url) ? "Fixture loader" : "Network or URLCache"
        }
    }
}

/// A failure in two lines: the case and the loader's code, then what the
/// loader said.
private struct ErrorRow: View {
    let error: ImagePipeline.Error

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent("Error") {
                Text(error.demoSummary)
                    .foregroundStyle(.red)
            }
            Text(error.demoMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
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

    /// What the last `data(for:)` call returned.
    struct DataResult {
        /// The size and the type, "328 KB · image/heic".
        let summary: String
        let source: String
        let duration: TimeInterval
    }

    @Published private(set) var isLoadingData = false
    @Published private(set) var data: DataResult?
    @Published private(set) var dataError: ImagePipeline.Error?

    private var task: ImageTask?
    private var observer: Task<Void, Never>?
    private var dataTask: Task<Void, Never>?

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
        let request = ImageRequest(url: DemoImages.heic, options: options)

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
        // The observer is gone before the task's `.cancelled` would reach it.
        if state == .loading {
            state = .cancelled
        }
    }

    /// Loads the bytes of the same image, with nothing decoded.
    func loadData() {
        dataTask?.cancel()
        data = nil
        dataError = nil
        isLoadingData = true

        let request = ImageRequest(url: DemoImages.heic)
        let startTime = Date()
        dataTask = Task { [weak self] in
            do throws(ImagePipeline.Error) {
                // Cancelling the Swift task cancels the load.
                let (data, response) = try await ImagePipeline.shared.data(for: request)
                self?.data = DataResult(
                    summary: "\(demoByteCount(data.count)) · \(Self.type(of: data, response: response))",
                    source: Self.source(of: response, request: request),
                    duration: Date().timeIntervalSince(startTime)
                )
            } catch {
                self?.dataError = error
            }
            self?.isLoadingData = false
        }
    }

    /// The type the server said, or, for data read from a disk cache, which
    /// comes with no response, the one its first bytes say.
    private static func type(of data: Data, response: URLResponse?) -> String {
        if let mimeType = response?.mimeType {
            return mimeType
        }
        return AssetType(data)?.rawValue ?? "unknown type"
    }

    /// Only a read from the disk cache comes without a response.
    private static func source(of response: URLResponse?, request: ImageRequest) -> String {
        guard response != nil else {
            return "Disk cache"
        }
        return DemoFixture.isFixture(request.url) ? "Fixture loader" : "Network or URLCache"
    }
}
