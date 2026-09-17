// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import AVFoundation
import NukeUI
import NukeVideo
import SwiftUI

/// Demonstrates NukeVideo: ``ImageDecoders/Video`` turns an MP4 into a poster
/// frame and an `AVAsset`, and ``VideoPlayerView`` plays the asset.
///
/// ```swift
/// ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
/// ```
///
/// The app registers the decoder once, in ``NukeDemoApp``, and from then on
/// every pipeline that asks the shared registry decodes video. The response
/// is an ordinary ``ImageContainer``: the frame at 0 s in `image`, the file as
/// downloaded in `data`, and an asset that reads that data in
/// `userInfo[.videoAssetKey]`. NukeUI doesn't play video by itself:
/// `LazyImage`'s default content shows the poster, and an app that wants the
/// video puts a player in the content, as the player pane does.
///
/// The decoder doesn't fail. For data it can take no frame from, it returns an
/// empty image and an asset that won't play, and the task succeeds. So the
/// screen checks the poster's size and the asset's `isPlayable` rather than
/// trusting the result.
struct VideoDemo: View {
    @State private var model = VideoDemoModel()
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        // The panes above the figures, except on a phone on its side, which
        // has the width for both and not the height.
        let isSideBySide = verticalSizeClass == .compact
        let layout = isSideBySide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        let stage = VideoStage(model: model)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        layout {
            if isSideBySide {
                ScrollView {
                    stage
                }
                .frame(maxWidth: 400)
            } else {
                stage
            }
            Divider()
            VideoFigures(model: model)
        }
        .background(Color(.systemGroupedBackground))
        .task {
            while !Task.isCancelled {
                model.sample()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Video",
        "NukeVideo lets the pipeline load short videos the way it loads images. `ImageDecoders.Video` makes a poster frame and an `AVAsset` from the downloaded file, and `VideoPlayerView` plays the asset. One request fills both panes.",
        code: """
        // Once, at launch
        ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)

        // In SwiftUI
        LazyImage(url: url) { state in
            if let container = state.imageContainer,
               container.image.size != .zero,
               let asset = container.userInfo[.videoAssetKey] as? AVAsset {
                VideoPlayer(asset: asset) // wraps VideoPlayerView
            } else if state.isLoading {
                ProgressView()
            } else {
                FailureView()
            }
        }
        """,
        points: [
            .init("Registering", "`ImageDecoders.Video` is in the NukeVideo module, and a pipeline uses it only once it is in the registry. This app registers it in `NukeDemoApp`, so every pipeline that asks `ImageDecoderRegistry.shared` – all of the demo's – decodes video. It takes MP4, M4V, and QuickTime files, which it tells by their `ftyp` box, and passes on anything else."),
            .init("The response", "An ordinary `ImageContainer`: `image` is the frame at 0 s, from `AVAssetImageGenerator`; `type` is `.mp4`; `data` is the file as downloaded; and `userInfo[.videoAssetKey]` is an `AVAsset` whose resource loader answers from that data, so the player never downloads the file again. The decoder runs on the decoding queue."),
            .init("Displaying", "NukeUI doesn't play video. `LazyImage`'s default content shows the poster, a still; to play the video, put a `VideoPlayerView` in the content, as above, with a `UIViewRepresentable`. In UIKit, `LazyImageView.makeImageView` can return one for a container that has an asset. Here the poster stays under the player until its first frame is up, so the pane never goes black."),
            .init("VideoPlayerView", "Muted, on a loop (`isLooping`), and filling its bounds (`videoGravity`). `play()` makes a player for the asset and starts it once the item is ready. The view resumes when it comes back on screen, or the app to the foreground. Without the loop, `onVideoFinished` is called at the end."),
            .init("Caching", "The memory cache keeps the whole container – the poster, the data, and the asset – and counts both the poster's bitmap and the data against its limit, so Reload plays the same asset at once. The disk cache keeps the file as downloaded: after Clear Memory, the decoder runs on it again and makes a new poster and a new asset."),
            .init("Keep the data", "Store the original data for video: `.storeOriginalData`, as here, or `.automatic`. Under `.storeEncodedImages`, the pipeline stores a JPEG of the poster under the video's key instead, and a load from disk comes back a still, with no asset."),
            .init("When it isn't a video", "For data it can take no frame from, such as a file cut short, the decoder doesn't throw: it returns an empty image and an asset that won't play, and the task succeeds. Check the poster's size, or the asset's `isPlayable`, as this screen does, before showing a player."),
            .init("Offline", "Offline, the video is a 2 s, 320×240 fixture bundled with the app, whose frames count up from 1.")
        ]
    )
}

// MARK: - Stage

/// The player and the poster, side by side, and the cache controls.
private struct VideoStage: View {
    let model: VideoDemoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                pane("Player", "VideoPlayerView in LazyImage") {
                    player
                }
                pane("Poster", "container.image") {
                    poster
                }
            }
            .frame(maxWidth: 560)
            HStack(spacing: 8) {
                Button("Reload", systemImage: "arrow.clockwise") { model.reload() }
                Button("Clear Memory") { model.clear([.memory]) }
                Button("Clear All", role: .destructive) { model.clear([.all]) }
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func pane(_ title: String, _ subtitle: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SquareCell {
                ZStack {
                    Color(.secondarySystemGroupedBackground)
                    content()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                Text(subtitle)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// What an app writes: the player once there is a poster and an asset,
    /// the poster under it until the video's first frame is up.
    private var player: some View {
        LazyImage(request: model.request) { state in
            if let container = state.imageContainer, container.image.size != .zero,
               let asset = container.userInfo[.videoAssetKey] as? AVAsset {
                ZStack {
                    state.image?
                        .resizable()
                        .scaledToFill()
                    VideoPlayerRepresentable(asset: asset, onMake: model.attach)
                }
            } else if state.isLoading || state.result == nil {
                ProgressView()
            } else if state.error != nil {
                VideoFailureSymbol(title: "failed")
            } else {
                VideoFailureSymbol(title: state.imageContainer?.image.size == .zero ? "no frame" : "no video")
            }
        }
        .pipeline(model.pipeline)
        .onStart { model.didStart($0) }
        .onCompletion { model.didComplete($0) }
        .id(model.loadID)
    }

    @ViewBuilder
    private var poster: some View {
        switch model.load?.result {
        case .success(let response) where response.image.size != .zero:
            Image(uiImage: response.image)
                .resizable()
                .scaledToFit()
        case .success:
            VideoFailureSymbol(title: "0×0")
        case .failure:
            VideoFailureSymbol(title: "failed")
        case nil:
            ProgressView()
        }
    }
}

private struct VideoFailureSymbol: View {
    let title: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
            Text(title)
                .font(.system(.caption, design: .monospaced))
        }
        .foregroundStyle(.red)
    }
}

/// `VideoPlayerView` from NukeVideo in SwiftUI. It plays the asset muted and
/// on a loop, and starts over with a new asset.
private struct VideoPlayerRepresentable: UIViewRepresentable {
    let asset: AVAsset
    /// Hands the view over, for the screen to read its player.
    var onMake: @MainActor (VideoPlayerView) -> Void = { _ in }

    func makeUIView(context: Context) -> VideoPlayerView {
        let view = VideoPlayerView()
        view.asset = asset
        view.play()
        onMake(view)
        return view
    }

    func updateUIView(_ view: VideoPlayerView, context: Context) {
        guard view.asset !== asset else { return }
        view.asset = asset
        view.play()
        onMake(view)
    }
}

// MARK: - Figures

/// What the response holds, what the asset is, and what the caches keep.
private struct VideoFigures: View {
    let model: VideoDemoModel

    var body: some View {
        List {
            if let problem = model.problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            Section {
                response
            } header: {
                Text("Response")
            } footer: {
                Text(responseFooter)
            }
            Section {
                asset
            } header: {
                Text("Asset")
            } footer: {
                Text("`userInfo[.videoAssetKey]`: an `AVURLAsset` that reads the container's data, so the player doesn't download the file again.")
            }
            Section {
                row("Memory", model.memory.count == 0 ? "empty" : "\(model.memory.count) \(model.memory.count == 1 ? "container" : "containers") · \(demoByteCount(model.memory.cost))")
                row("Disk", disk)
            } header: {
                Text("Caches")
            } footer: {
                Text("The memory cache keeps the container – the poster, the data, and the asset – so Reload plays the same asset. The disk cache keeps the file: after Clear Memory, the decoder makes a new poster and a new asset from it.")
            }
            Section {
                DemoLink(.imageFormats)
                DemoLink(.caching)
            } header: {
                Text("See Also")
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Response

    private var responseFooter: LocalizedStringKey {
        switch model.load?.result {
        case .failure:
            "The load failed before a decoder saw any data."
        case .success(let response) where response.cacheType == .memory:
            "From the memory cache: the container a decoder made earlier, served without a task."
        case .success(let response) where response.container.userInfo[.videoAssetKey] == nil:
            "The pipeline asked `ImageDecoderRegistry` for a decoder, and `ImageDecoders.Video` passed: the data isn't a video."
        default:
            "One request. The pipeline asked `ImageDecoderRegistry` for a decoder, and `ImageDecoders.Video`, which the app registered at launch, took the data."
        }
    }

    @ViewBuilder
    private var response: some View {
        switch model.load?.result {
        case nil:
            row("Source", model.isLoading ? "loading…" : "–")
        case .failure(let error):
            row("Source", "failed · \(error.demoDetail)", tint: .red)
        case .success(let response):
            let load = model.load
            row("Source", source(response, bytes: load?.metrics?.bytes?.downloaded))
            row("Decoder", decoder(response, metrics: load?.metrics))
            row("Type", response.container.type.demoLiteral)
            let frame = poster(response.image)
            row("Poster", frame.text, tint: frame.tint)
            row("Data", response.container.data.map { "\(demoByteCount($0.count)), kept for the player" } ?? "none")
            row("Memory cost", memoryCost(response.container))
        }
    }

    private func source(_ response: ImageResponse, bytes: Int64?) -> String {
        switch response.cacheType {
        case .memory?:
            return "memory cache"
        case .disk?:
            return "disk cache"
        case nil:
            let origin = DemoFixture.isFixture(model.request.url) ? "fixture loader" : "network"
            return bytes.map { "\(origin) · \(demoByteCount($0))" } ?? origin
        }
    }

    private func decoder(_ response: ImageResponse, metrics: ImageTask.Metrics?) -> String {
        guard response.cacheType != .memory else {
            return "not asked: from memory"
        }
        let stage = metrics?.jobs.flatMap(\.stages).last { $0.kind == .decode }
        guard let stage, let name = stage.decoder else {
            return "–"
        }
        let time = stage.workDuration.map { " · \(demoMilliseconds($0))" } ?? ""
        return demoRecordedTypeName(name) + time
    }

    private func poster(_ image: UIImage) -> (text: String, tint: Color?) {
        guard let cgImage = image.cgImage, image.size != .zero else {
            return ("0×0 · no frame", .red)
        }
        return ("\(cgImage.width)×\(cgImage.height) · the frame at 0 s", nil)
    }

    /// What the memory cache charges for the container: the poster's bitmap
    /// and the data.
    private func memoryCost(_ container: ImageContainer) -> String {
        let bitmap = container.image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        let data = container.data?.count ?? 0
        return "\(demoByteCount(bitmap + data)) · \(demoByteCount(bitmap)) + \(demoByteCount(data))"
    }

    // MARK: Asset

    @ViewBuilder
    private var asset: some View {
        if let asset = model.asset {
            row("Object", "\(asset.className) #\(asset.number) · \(asset.isNew ? "new" : "reused")")
            switch asset.details {
            case .loading:
                row("Video", "loading…")
            case .failed(let message):
                row("Video", "failed · \(message)", tint: .red)
            case let .loaded(duration, size, frameRate, isPlayable):
                let parts = [size.map { "\(Int($0.width))×\(Int($0.height))" }, frameRate.map { "\(Int($0.rounded())) fps" }, demoSeconds(duration)]
                row("Video", parts.compactMap { $0 }.joined(separator: " · "))
                row("Playable", isPlayable ? "yes" : "no", tint: isPlayable ? nil : .red)
            }
            let playing = playback
            row("Playback", playing.text, tint: playing.tint)
        } else {
            row("Object", model.load == nil ? "–" : "none")
        }
    }

    private var playback: (text: String, tint: Color?) {
        guard let playback = model.playback else {
            return ("–", nil)
        }
        if let error = playback.error {
            return ("failed · \(error)", .red)
        }
        guard playback.isReady else {
            return ("waiting for the first frame", nil)
        }
        var text = demoSeconds(playback.time)
        if case let .loaded(duration, _, _, _)? = model.asset?.details {
            text += " of \(demoSeconds(duration))"
        }
        if playback.loopCount > 0 {
            text += " · loop \(playback.loopCount + 1)"
        }
        if playback.rate == 0 {
            text += " · paused"
        }
        return (text, nil)
    }

    // MARK: Caches

    private var disk: String {
        guard let entry = model.disk else {
            return "empty"
        }
        return "\(entry.type.demoLiteral) · \(demoByteCount(entry.byteCount))"
    }

    private func row(_ title: String, _ value: String, tint: Color? = nil) -> some View {
        LabeledContent(title) {
            DemoMonoLabel(value, tint: tint)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Model

/// The screen's pipeline, the load, and what the player is doing.
@MainActor @Observable
private final class VideoDemoModel {
    /// Made the first time the screen asks rather than in `init`, which
    /// SwiftUI runs each time it makes the view, keeping only the first
    /// model: each pipeline would open the disk cache again.
    @ObservationIgnored private(set) lazy var pipeline = makePipeline()
    /// Made when the screen opens: a screen opened offline loads the fixture.
    let request: ImageRequest
    /// Changes to load again: the player pane is a new view each time.
    private(set) var loadID = 0
    private(set) var isLoading = false
    private(set) var load: Load?
    private(set) var asset: AssetFigures?
    private(set) var playback: Playback?
    private(set) var memory: (count: Int, cost: Int) = (0, 0)
    private(set) var disk: DiskEntry?

    struct Load {
        let result: Result<ImageResponse, ImagePipeline.Error>
        /// `nil` for a container from memory, which takes no task.
        let metrics: ImageTask.Metrics?
    }

    struct AssetFigures {
        let className: String
        /// Counts the asset objects the screen has seen.
        let number: Int
        let isNew: Bool
        var details: Details

        enum Details {
            case loading
            case loaded(duration: TimeInterval, size: CGSize?, frameRate: Float?, isPlayable: Bool)
            case failed(String)
        }
    }

    struct Playback {
        let time: TimeInterval
        let loopCount: Int
        let isReady: Bool
        let rate: Float
        let error: String?
    }

    struct DiskEntry: Sendable {
        let byteCount: Int
        let type: AssetType?
    }

    private let imageCache = ImageCache()
    @ObservationIgnored private var task: ImageTask?
    @ObservationIgnored private var lastAsset: AVAsset?
    @ObservationIgnored private var assetCount = 0
    @ObservationIgnored private var assetTask: Task<Void, Never>?
    @ObservationIgnored private var diskTask: Task<Void, Never>?
    @ObservationIgnored private weak var playerView: VideoPlayerView?
    @ObservationIgnored private var lastTime: TimeInterval?
    @ObservationIgnored private var loopCount = 0

    init() {
        request = ImageRequest(url: DemoImages.video)
    }

    private func makePipeline() -> ImagePipeline {
        // A memory cache of the screen's own, so the first load of a visit
        // comes from the disk or the network, and a disk cache that keeps
        // the file between visits.
        var configuration = ImagePipeline.Configuration.withDataCache(name: "com.github.kean.NukeDemo.Video")
        configuration.imageCache = imageCache
        configuration.isDiagnosticsEnabled = true
        return DemoPipelineProbe.makePipeline("Video", configuration: configuration)
    }

    private var dataCache: DataCache? {
        pipeline.configuration.dataCache as? DataCache
    }

    /// Why the screen doesn't show a video, or `nil`.
    var problem: String? {
        switch load?.result {
        case .failure(let error):
            return "The load failed: \(error.demoDetail)."
        case .success(let response) where response.image.size == .zero:
            return "The pipeline reported success, but the decoder took no frame from the data: it isn't a video AVFoundation can read. ImageDecoders.Video returns an empty image rather than throw, so the screen counts it as a failure."
        case .success(let response) where response.container.userInfo[.videoAssetKey] == nil:
            return "The response is a still, \(response.container.type.demoLiteral), with no asset to play: a decoder other than ImageDecoders.Video took the data."
        default:
            break
        }
        if case .loaded(_, _, _, isPlayable: false)? = asset?.details {
            return "The asset won't play."
        }
        if let error = playback?.error {
            return "The player failed: \(error)."
        }
        return nil
    }

    // MARK: Loading

    func didStart(_ task: ImageTask) {
        self.task = task
        isLoading = true
    }

    func didComplete(_ result: Result<ImageResponse, ImagePipeline.Error>) {
        // A container from memory comes without a task.
        let metrics = (try? result.get().cacheType) == .memory ? nil : task?.metrics
        task = nil
        isLoading = false
        load = Load(result: result, metrics: metrics)
        if case .success(let response) = result, let asset = response.container.userInfo[.videoAssetKey] as? AVAsset {
            inspect(asset)
        } else {
            asset = nil
        }
        refreshDisk()
    }

    func reload() {
        task = nil
        isLoading = false
        load = nil
        asset = nil
        playback = nil
        playerView = nil
        loadID += 1
    }

    func clear(_ caches: ImagePipeline.Cache.Caches) {
        pipeline.cache.removeAll(caches: caches)
        reload()
        refreshDisk()
    }

    // MARK: Asset

    private func inspect(_ asset: AVAsset) {
        let isNew = asset !== lastAsset
        if isNew {
            assetCount += 1
            lastAsset = asset
        }
        self.asset = AssetFigures(className: String(describing: type(of: asset)), number: assetCount, isNew: isNew, details: .loading)
        assetTask?.cancel()
        assetTask = Task {
            let details: AssetFigures.Details
            do {
                let (duration, isPlayable) = try await asset.load(.duration, .isPlayable)
                var size: CGSize?
                var frameRate: Float?
                if let track = try await asset.loadTracks(withMediaType: .video).first {
                    let (naturalSize, nominalFrameRate) = try await track.load(.naturalSize, .nominalFrameRate)
                    size = naturalSize
                    frameRate = nominalFrameRate
                }
                details = .loaded(duration: duration.seconds, size: size, frameRate: frameRate, isPlayable: isPlayable)
            } catch {
                details = .failed(error.localizedDescription)
            }
            guard !Task.isCancelled else { return }
            self.asset?.details = details
        }
    }

    // MARK: Player

    /// Called by the player pane with the view it made.
    func attach(_ view: VideoPlayerView) {
        playerView = view
        lastTime = nil
        loopCount = 0
    }

    /// Reads the player and the memory cache: ten times a second.
    func sample() {
        if memory.count != imageCache.totalCount || memory.cost != imageCache.totalCost {
            memory = (imageCache.totalCount, imageCache.totalCost)
        }
        guard let view = playerView, view.asset != nil, let player = view.playerLayer.player else {
            if playback != nil {
                playback = nil
            }
            return
        }
        let time = player.currentTime().seconds
        // The view seeks back to the start at the end of every loop.
        if let lastTime, time + 0.5 < lastTime {
            loopCount += 1
        }
        lastTime = time
        let error = player.currentItem?.error ?? player.error
        playback = Playback(
            time: time.isFinite ? time : 0,
            loopCount: loopCount,
            isReady: view.playerLayer.isReadyForDisplay,
            rate: player.rate,
            error: error?.localizedDescription
        )
    }

    // MARK: Disk

    /// Reads the cache's entry for the request. A write waits in the cache's
    /// staging area for a moment before it reaches the disk, and the cache
    /// answers from there too.
    private func refreshDisk() {
        guard let dataCache else { return }
        let key = pipeline.cache.makeDataCacheKey(for: request)
        diskTask?.cancel()
        diskTask = Task {
            // The pipeline stores the file on its own schedule, around the
            // time it decodes it.
            for delay in [200, 1_000] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                disk = await Task.detached {
                    dataCache.cachedData(for: key).map { DiskEntry(byteCount: $0.count, type: AssetType($0)) }
                }.value
            }
        }
    }}
