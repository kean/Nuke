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
    @State private var selection = ProgressiveDecodingDemoModel.Encoding.progressive
    /// `nil` until the screen is measured, which decides what it loads.
    @State private var width: CGFloat?

    /// The encodings on screen: both side by side where each still gets a
    /// picture 300 points wide, the one the picker selects where they don't.
    private var encodings: [ProgressiveDecodingDemoModel.Encoding] {
        guard let width else { return [] }
        return width >= 2 * 300 + 16 + 32 ? ProgressiveDecodingDemoModel.Encoding.allCases : [selection]
    }

    var body: some View {
        let encodings = encodings
        ScrollView {
            VStack(spacing: 16) {
                if encodings.count == 1 {
                    Picker("Encoding", selection: $selection) {
                        ForEach(ProgressiveDecodingDemoModel.Encoding.allCases) { encoding in
                            Text(encoding.title).tag(encoding)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack(alignment: .top, spacing: 16) {
                    ForEach(encodings) { encoding in
                        ProgressiveDecodingPane(
                            encoding: encoding,
                            load: model.loads[encoding],
                            showsTitle: encodings.count > 1
                        )
                    }
                }

                Button("Restart") { model.load(encodings) }
                    .buttonStyle(.bordered)
            }
            .padding(16)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // Starts over when the encodings on screen change: with the picker,
        // or when the screen gets room for both or loses it.
        .task(id: encodings) {
            if !encodings.isEmpty {
                model.load(encodings)
            }
        }
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
            .init("Baseline", "A baseline JPEG has nothing to show until the download completes. Where the screen has room, the two load side by side; where it doesn't, switch the picker to watch the difference."),
            .init("Previews", "Every preview is a full image. `ImageResponse.isPreview` is what tells them apart from the final one."),
            .init("The count", "The badge is `ImageContainer.UserInfoKey.scanNumberKey`: the number of previews this load has decoded, not the index of a scan in the file. Image I/O doesn't say where a scan ends, the decoder makes a preview of every chunk it can decode, and the pipeline skips a chunk while it is still decoding the last one."),
            .init("Restart", "Restart cancels the loads on screen and starts them again. The server supports range requests, so a new load resumes where the old one stopped: its first preview already has every scan the old one kept, and its count starts from 1."),
            .init("Cost", "Each scan is decoded, so progressive decoding trades CPU for a picture that appears sooner. The pipeline skips a scan if it is still decoding the previous one.")
        ]
    )
}

/// One encoding: its title, if the other is beside it, the picture, and how
/// far its load has got.
private struct ProgressiveDecodingPane: View {
    let encoding: ProgressiveDecodingDemoModel.Encoding
    let load: ProgressiveDecodingDemoModel.Load?
    let showsTitle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle {
                Text(encoding.title)
                    .font(.headline)
            }

            ZStack {
                Color(.secondarySystemBackground)
                if let image = load?.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            let progress = load?.progress ?? ImageTask.Progress(completed: 0, total: 0)
            ProgressView(value: progress.fraction)
            HStack {
                Text("\(demoByteCount(progress.completed)) / \(demoByteCount(progress.total))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if let previewNumber = load?.previewNumber {
                    DemoBadge("Preview \(previewNumber)")
                }
                if load?.isFinal == true {
                    DemoBadge("Final", color: .green)
                }
                if load?.error != nil {
                    DemoBadge("Failed", color: .red)
                }
            }
            if let resumedByteCount = load?.resumedByteCount {
                Text(encoding == .progressive
                     ? "Resumed from \(demoByteCount(resumedByteCount)): the first preview has every scan the earlier load kept, and the count starts over."
                     : "Resumed from \(demoByteCount(resumedByteCount)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = load?.error {
                Text(error.demoMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
private final class ProgressiveDecodingDemoModel: ObservableObject {
    enum Encoding: CaseIterable, Identifiable {
        case progressive
        case baseline

        var id: Self { self }

        var title: String {
            switch self {
            case .progressive: "Progressive"
            case .baseline: "Baseline"
            }
        }

        var url: URL {
            switch self {
            case .progressive: DemoImages.progressiveJPEG
            case .baseline: DemoImages.baselineJPEG
            }
        }
    }

    /// What one load has delivered so far.
    struct Load {
        /// Identifies the load in the probe's events, which a cancelled load
        /// can still be sending.
        let id: Int
        var image: UIImage?
        var progress = ImageTask.Progress(completed: 0, total: 0)
        /// The previews this load has decoded, as the decoder numbers them.
        var previewNumber: Int?
        /// The bytes the load didn't download again, if it resumed.
        var resumedByteCount: Int?
        var isFinal = false
        var error: ImagePipeline.Error?
    }

    @Published private(set) var loads: [Encoding: Load] = [:]

    private var tasks: [ImageTask] = []
    private var observers: [Task<Void, Never>] = []
    private var lastLoadID = 0

    /// A pipeline with progressive decoding enabled. The caches are disabled
    /// so that every run starts from scratch.
    private let pipeline: ImagePipeline

    init() {
        var configuration = ImagePipeline.Configuration()
        configuration.dataLoader = ThrottledDataLoader()
        configuration.imageCache = nil
        configuration.isProgressiveDecodingEnabled = true
        configuration.isStoringPreviewsInMemoryCache = false
        configuration.isTaskCoalescingEnabled = false

        // A download that resumes goes out with a `Range` header, which the
        // probe reports as the delegate hands the request on.
        let relay = DemoRelay<ProgressiveDecodingDemoModel>()
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

    /// Cancels what is loading and loads `encodings` from the start, at the
    /// same time.
    func load(_ encodings: [Encoding]) {
        cancel()
        loads = [:]
        for encoding in encodings {
            start(encoding)
        }
    }

    private func start(_ encoding: Encoding) {
        lastLoadID += 1
        let loadID = lastLoadID
        loads[encoding] = Load(id: loadID)

        var request = ImageRequest(url: encoding.url)
        request.userInfo[.loadIDKey] = loadID
        let task = pipeline.imageTask(with: request)
        tasks.append(task)

        observers.append(Task { [weak self] in
            for await event in task.events {
                guard let self, self.loads[encoding]?.id == loadID else { return }
                switch event {
                case .progress(let progress):
                    self.loads[encoding]?.progress = progress
                case .preview(let response):
                    // A partially decoded image: the scans of a progressive
                    // JPEG that have arrived so far.
                    self.loads[encoding]?.image = response.image
                    self.loads[encoding]?.previewNumber = response.container.userInfo[.scanNumberKey] as? Int
                case .finished(let result):
                    switch result {
                    case .success(let response):
                        self.loads[encoding]?.image = response.image
                        self.loads[encoding]?.isFinal = true
                    case .failure(.cancelled):
                        break
                    case .failure(let error):
                        self.loads[encoding]?.error = error
                    }
                }
            }
        })
    }

    func cancel() {
        observers.forEach { $0.cancel() }
        observers = []
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    fileprivate func didResume(from byteCount: Int, loadID: Int) {
        guard let encoding = loads.first(where: { $0.value.id == loadID })?.key else { return }
        loads[encoding]?.resumedByteCount = byteCount
    }

    /// `N` of `bytes=N-`, the only range the pipeline asks for.
    nonisolated private static func firstByte(ofRange range: String) -> Int? {
        guard range.hasPrefix("bytes="), range.hasSuffix("-") else { return nil }
        return Int(range.dropFirst("bytes=".count).dropLast())
    }
}

extension ImageRequest.UserInfoKey {
    fileprivate static let loadIDKey: ImageRequest.UserInfoKey = "com.github.kean.NukeDemo.ProgressiveDecoding.load"
}
