// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

#if DEBUG && (os(iOS) || os(visionOS))

import SwiftUI
import UIKit
import Nuke

#Preview("Image View") {
    ImageLoaderPreview()
}

/// Scrolling while the images load checks that a reused cell never shows the
/// image of the previous item; scrolling back, that memory cache hits appear
/// without the placeholder or the transition.
@available(iOS 17, *)
#Preview("Cell Reuse (Slow Network)") {
    PreviewGridViewController()
}

// MARK: - Playground

/// Loads images into an image view, and prints every state of its loader to
/// the console.
private struct ImageLoaderPreview: View {
    @State private var imageView = UIImageView()
    @State private var isSlow = false
    @State private var keepsPreviousImage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreviewViewHost(view: imageView)
                .frame(height: 240)
                .background(Color(.secondarySystemBackground))
            HStack {
                Button("Image 1") { start(PreviewImages.samples[0]) }
                Button("Image 2") { start(PreviewImages.samples[1]) }
                Button("Progressive") { start(PreviewImages.progressive) }
                Button("404") { start(PreviewImages.broken) }
                Button("nil") { start(nil) }
            }
            HStack {
                Button("Cancel") { loader.cancel() }
                Button("Reset") { loader.reset() }
                Button("Clear Memory Cache") { PreviewPipelines.removeAllFromMemory() }
            }
            Toggle("Slow network (2 s)", isOn: $isSlow)
            Toggle("Keep previous image", isOn: $keepsPreviousImage)
            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding()
        .onAppear { start(PreviewImages.samples[0]) }
    }

    /// The loader attached to the image view, which `load(_:into:)` uses.
    private var loader: ImageLoader { ImageLoader.loader(for: imageView) }

    private func start(_ url: URL?) {
        imageView.contentMode = .scaleAspectFit
        loader.keepsPreviousImage = keepsPreviousImage
        loader.delegate = PreviewLogger.shared
        PreviewLogger.shared.begin(url)
        let handle = ImageLoader.load(url, into: imageView, presentation: .init(
            placeholder: PreviewImages.swatch(.systemGray4),
            transition: .fadeIn(duration: 0.33),
            failureImage: PreviewImages.swatch(.systemRed)
        ), pipeline: isSlow ? PreviewPipelines.slow : PreviewPipelines.fast)
        Task {
            let result = await handle.result
            PreviewLogger.shared.log("await: \(PreviewLogger.describe(result))")
        }
    }
}

/// Prints the states of a loader, with the time since the load began.
@MainActor
private final class PreviewLogger: ImageLoaderDelegate {
    static let shared = PreviewLogger()

    private var startTime = Date()

    func begin(_ url: URL?) {
        startTime = Date()
        print("[ImageLoader] load \(url?.lastPathComponent ?? "nil")")
    }

    func log(_ message: String) {
        let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
        print("[ImageLoader] \(elapsed) ms  \(message)")
    }

    func imageLoader(_ loader: ImageLoader, didUpdate state: ImageLoader.State) {
        switch state.event {
        case .started:
            log(state.isPreviousImage ? "started, keeps the previous image" : state.imageContainer != nil ? "started, cached preview" : "started")
        case .progress(let progress):
            log("progress \(progress.completed)/\(progress.total)")
        case .preview:
            log("preview")
        case let .finished(result, isSync):
            log("finished: \(Self.describe(result))\(isSync ? ", sync" : "")")
        case .cancelled:
            log("cancelled")
        case .reset:
            log("reset")
        }
    }

    static func describe(_ result: Result<ImageResponse, ImagePipeline.Error>) -> String {
        switch result {
        case .success(let response): "success from \(response.cacheType.map { "\($0)" } ?? "network")"
        case .failure(let error): "failure \(error)"
        }
    }
}

// MARK: - Cell Reuse

private final class PreviewGridViewController: UICollectionViewController {
    init() {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 96, height: 96)
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        super.init(collectionViewLayout: layout)
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        300
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        let imageView = cell.backgroundView as? UIImageView ?? UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        cell.backgroundView = imageView

        let url = PreviewImages.grid[indexPath.item % PreviewImages.grid.count]
        ImageLoader.load(url, into: imageView, presentation: .init(
            placeholder: PreviewImages.swatch(.systemGray4),
            transition: .fadeIn(duration: 0.25)
        ), pipeline: PreviewPipelines.slow)
        return cell
    }
}

// MARK: - Helpers

private struct PreviewViewHost: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView {
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}

    // Fills the proposed size instead of growing to the size of the image.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

private enum PreviewPipelines {
    static let fast = ImagePipeline {
        $0.isProgressiveDecodingEnabled = true
    }

    static let slow = ImagePipeline {
        $0.dataLoader = SlowDataLoader()
        $0.isProgressiveDecodingEnabled = true
    }

    static func removeAllFromMemory() {
        fast.cache.removeAll(caches: [.memory])
        slow.cache.removeAll(caches: [.memory])
    }
}

/// Waits two seconds before it starts loading. A cancelled load still
/// downloads, and the pipeline ignores its data.
private struct SlowDataLoader: DataLoading {
    private let base = DataLoader()

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        let base = self.base
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            _ = base.loadData(with: request, didReceiveData: didReceiveData, completion: completion)
        }
        return NoCancellation()
    }

    private struct NoCancellation: Cancellable {
        func cancel() {}
    }
}

@MainActor
private enum PreviewImages {
    static let samples = [
        URL(string: "https://cloud.githubusercontent.com/assets/1567433/9781817/ecb16e82-57a0-11e5-9b43-6b4f52659997.jpg")!,
        URL(string: "https://cloud.githubusercontent.com/assets/1567433/9781832/0719dd5e-57a1-11e5-9324-9764de25ed47.jpg")!
    ]

    static let progressive = URL(string: "https://user-images.githubusercontent.com/1567433/120257587-7fb1b880-c25e-11eb-93d1-7e7df2b9f5ca.jpeg")!

    static let broken = URL(string: "https://kean.blog/images/this-image-does-not-exist.jpeg")!

    static let grid = [
        "9781817/ecb16e82-57a0-11e5-9b43-6b4f52659997",
        "9781832/0719dd5e-57a1-11e5-9324-9764de25ed47",
        "9781833/09021316-57a1-11e5-817b-85b57a2a8a77",
        "9781834/0931ad74-57a1-11e5-9080-c8f6ecea19ce",
        "9781838/0e6274f4-57a1-11e5-82fd-872e735eea73",
        "9781839/0e63ad92-57a1-11e5-8841-bd3c5ea1bb9c",
        "9781843/0f4064b2-57a1-11e5-9fb7-f258e81a4214",
        "9781840/0e95f978-57a1-11e5-8179-36dfed72f985",
        "9781841/0e96b5fc-57a1-11e5-82ae-699b113bb85a",
        "9781894/839cf99c-57a1-11e5-9602-d56d99a31abc",
        "9781896/83c5e1f4-57a1-11e5-9961-97730da2a7ad",
        "9781897/83c622cc-57a1-11e5-98dd-3a7d54b60170"
    ].map { URL(string: "https://cloud.githubusercontent.com/assets/1567433/\($0).jpg")! }

    /// A square of the given color: a placeholder an aspect-fit image view
    /// shows as a square in its middle.
    static func swatch(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}

#endif
