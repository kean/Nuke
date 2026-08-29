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
            DemoIntro("The data is delivered in small chunks with a delay between them so that the scans are visible on a fast connection. The baseline JPEG has nothing to show until the download completes.")

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
                    if let scanNumber = model.scanNumber {
                        DemoBadge("Scan \(scanNumber)")
                    }
                    if model.image != nil, !model.isLoading {
                        DemoBadge("Final", color: .green)
                    }
                }
            }
            .padding(16)

            Button("Restart") { model.load() }
                .buttonStyle(.bordered)

            Spacer()
        }
        .onAppear { model.loadIfNeeded() }
        .onDisappear { model.cancel() }
    }
}

@MainActor
private final class ProgressiveDecodingDemoModel: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var progress = ImageTask.Progress(completed: 0, total: 0)
    @Published private(set) var scanNumber: Int?
    @Published private(set) var isLoading = false

    @Published var isProgressive = true {
        didSet { load() }
    }

    private var task: ImageTask?
    private var observer: Task<Void, Never>?
    private var isStarted = false

    /// A pipeline with progressive decoding enabled. The caches are disabled
    /// so that every run starts from scratch.
    private let pipeline = ImagePipeline {
        $0.dataLoader = ThrottledDataLoader()
        $0.imageCache = nil
        $0.isProgressiveDecodingEnabled = true
        $0.isStoringPreviewsInMemoryCache = false
        $0.isTaskCoalescingEnabled = false
    }

    func loadIfNeeded() {
        guard !isStarted else { return }
        isStarted = true
        load()
    }

    func load() {
        cancel()

        image = nil
        scanNumber = nil
        progress = ImageTask.Progress(completed: 0, total: 0)
        isLoading = true

        let url = isProgressive ? DemoImages.progressiveJPEG : DemoImages.baselineJPEG
        let task = pipeline.imageTask(with: url)
        self.task = task

        observer = Task { [weak self] in
            for await event in task.events {
                guard let self else { return }
                switch event {
                case .progress(let progress):
                    self.progress = progress
                case .preview(let response):
                    // A partially decoded image: one scan of a progressive JPEG.
                    self.image = response.image
                    self.scanNumber = response.container.userInfo[.scanNumberKey] as? Int
                case .finished(let result):
                    self.isLoading = false
                    if case .success(let response) = result {
                        self.image = response.image
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
}
