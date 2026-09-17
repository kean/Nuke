// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import SwiftUI

/// Demonstrates progressive JPEG decoding.
///
/// ```swift
/// let pipeline = ImagePipeline {
///     $0.isProgressiveDecodingEnabled = true
/// }
/// ```
///
/// Once enabled, the pipeline delivers the scans of a progressive JPEG as
/// previews through the same task that delivers the final image.
struct ProgressiveDecodingDemo: View {
    @StateObject private var model = ProgressiveDecodingDemoModel()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Encoding", selection: $model.isProgressive) {
                Text("Progressive").tag(true)
                Text("Baseline").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(16)

            ZStack {
                Color(.secondarySystemBackground)
                if let image = model.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(4 / 3, contentMode: .fit)

            VStack(spacing: 12) {
                ProgressView(value: model.progress.fraction)
                HStack {
                    Text("\(demoByteCount(model.progress.completed)) / \(demoByteCount(model.progress.total))")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let previewNumber = model.previewNumber {
                        DemoBadge("Preview \(previewNumber)")
                    }
                    if model.isFinal {
                        DemoBadge("Final", color: .green)
                    }
                    if model.error != nil {
                        DemoBadge("Failed", color: .red)
                    }
                }
                if let resumedByteCount = model.resumedByteCount {
                    Text("Resumed from \(demoByteCount(resumedByteCount)): the first preview has every scan the earlier load kept, and the count starts over.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = model.error {
                    Text(error.demoMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)

            Button("Restart") { model.load() }
                .buttonStyle(.bordered)

            Spacer()
        }
        .onAppear { model.loadIfNeeded() }
        .onDisappear { model.cancel() }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Progressive Decoding",
        "A progressive JPEG is encoded as a series of scans, each one sharper than the last. With progressive decoding enabled, the pipeline delivers the scans as previews through the same task that delivers the final image.",
        code: """
        let pipeline = ImagePipeline {
            $0.isProgressiveDecodingEnabled = true
        }
        """,
        points: [
            .init("Throttled on purpose", "The demo delivers the data in small chunks with a delay between them. On a real connection the scans go by too fast to see."),
            .init("Baseline", "A baseline JPEG has nothing to show until the download completes. Switch the picker to watch the difference."),
            .init("Previews", "Every preview is a full image. `ImageResponse.isPreview` is what tells them apart from the final one."),
            .init("The count", "The badge is `ImageContainer.UserInfoKey.scanNumberKey`: the number of previews this load has decoded, not the index of a scan in the file. Image I/O doesn't say where a scan ends, the decoder makes a preview of every chunk it can decode, and the pipeline skips a chunk while it is still decoding the last one."),
            .init("Restart", "Restart cancels the load and starts a new one. The server supports range requests, so the new load resumes where the old one stopped: its first preview already has every scan the old one kept, and its count starts from 1."),
            .init("Cost", "Each scan is decoded, so progressive decoding trades CPU for a picture that appears sooner. The pipeline skips a scan if it is still decoding the previous one.")
        ]
    )
}

@MainActor
private final class ProgressiveDecodingDemoModel: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var progress = ImageTask.Progress(completed: 0, total: 0)
    /// The previews this load has decoded, as the decoder numbers them.
    @Published private(set) var previewNumber: Int?
    /// The bytes the current load didn't download again, if it resumed.
    @Published private(set) var resumedByteCount: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var isFinal = false
    @Published private(set) var error: ImagePipeline.Error?

    @Published var isProgressive = true {
        didSet { load() }
    }

    private var task: ImageTask?
    private var observer: Task<Void, Never>?
    private var isStarted = false

    /// A pipeline with progressive decoding enabled. The caches are disabled
    /// so that every run starts from scratch.
    private let pipeline: ImagePipeline

    /// Identifies a load in the probe's events, which a cancelled load can
    /// still be sending.
    private var loadID = 0

    init() {
        var configuration = ImagePipeline.Configuration()
        configuration.dataLoader = ThrottledDataLoader()
        configuration.imageCache = nil
        configuration.isProgressiveDecodingEnabled = true
        configuration.isStoringPreviewsInMemoryCache = false
        configuration.isTaskCoalescingEnabled = false

        // A download that resumes goes out with a `Range` header, which the
        // probe reports as the delegate hands the request on.
        let relay = ResumeRelay()
        pipeline = DemoPipelineProbe.makePipeline("Progressive Decoding", configuration: configuration, onEvent: { event in
            guard case .willLoadData(let urlRequest) = event.kind,
                  let loadID = event.request.userInfo[.loadIDKey] as? Int,
                  let byteCount = urlRequest.value(forHTTPHeaderField: "Range").flatMap(Self.firstByte(ofRange:)) else {
                return
            }
            Task { @MainActor in relay.model?.didResume(from: byteCount, loadID: loadID) }
        })
        relay.model = self
    }

    func loadIfNeeded() {
        guard !isStarted else { return }
        isStarted = true
        load()
    }

    func load() {
        cancel()

        image = nil
        previewNumber = nil
        resumedByteCount = nil
        isFinal = false
        error = nil
        progress = ImageTask.Progress(completed: 0, total: 0)
        isLoading = true

        loadID += 1
        var request = ImageRequest(url: isProgressive ? DemoImages.progressiveJPEG : DemoImages.baselineJPEG)
        request.userInfo[.loadIDKey] = loadID
        let task = pipeline.imageTask(with: request)
        self.task = task

        observer = Task { [weak self] in
            for await event in task.events {
                guard let self else { return }
                switch event {
                case .progress(let progress):
                    self.progress = progress
                case .preview(let response):
                    // A partially decoded image: the scans of a progressive
                    // JPEG that have arrived so far.
                    self.image = response.image
                    self.previewNumber = response.container.userInfo[.scanNumberKey] as? Int
                case .finished(let result):
                    self.isLoading = false
                    switch result {
                    case .success(let response):
                        self.image = response.image
                        self.isFinal = true
                    case .failure(.cancelled):
                        break
                    case .failure(let error):
                        self.error = error
                    }
                }
            }
        }
    }

    func cancel() {
        isLoading = false
        observer?.cancel()
        observer = nil
        task?.cancel()
        task = nil
    }

    fileprivate func didResume(from byteCount: Int, loadID: Int) {
        guard loadID == self.loadID else { return }
        resumedByteCount = byteCount
    }

    /// `N` of `bytes=N-`, the only range the pipeline asks for.
    nonisolated private static func firstByte(ofRange range: String) -> Int? {
        guard range.hasPrefix("bytes="), range.hasSuffix("-") else { return nil }
        return Int(range.dropFirst("bytes=".count).dropLast())
    }
}

/// Hands the probe's events to the model, which doesn't exist yet when the
/// pipeline is made. `@MainActor`, which makes it `Sendable`.
@MainActor
private final class ResumeRelay {
    weak var model: ProgressiveDecodingDemoModel?
}

extension ImageRequest.UserInfoKey {
    fileprivate static let loadIDKey: ImageRequest.UserInfoKey = "com.github.kean.NukeDemo.ProgressiveDecoding.load"
}
