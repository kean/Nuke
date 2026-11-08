// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI
import UIKit

/// `LazyImage` in the four places an app puts it – `List`, `LazyVStack`,
/// `LazyVGrid`, and a reused `UICollectionView` cell – with a count of what
/// every body drew.
///
/// A body that draws a placeholder, a failure, or the image of another request
/// while the memory cache has the image is stale. There should be none:
/// `LazyImage` draws an image from the memory cache in the first body that
/// loads its request, a cell that comes back on screen and a reused cell
/// included.
struct LazyImageReuseDemo: View {
    @State private var model = LazyImageReuseModel()

    var body: some View {
        VStack(spacing: 0) {
            LazyImageReuseHeader(model: model)
            Divider()
            content
                .id(model.generation)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LazyImageReuseOptions(model: model)
            }
        }
        .task {
            // Once the first screenful is up.
            guard DemoLaunchOptions.claimAutorun(for: .lazyImageReuse),
                  (try? await Task.sleep(for: .seconds(1))) != nil else { return }
            await model.runScrollBack()
        }
        .demoInfo(Self.info)
    }

    @ViewBuilder
    private var content: some View {
        switch model.container {
        case .list:
            ScrollViewReader { proxy in
                List(0..<model.rowCount, id: \.self) { row in
                    LazyImageReuseCell(row: row, style: .row, model: model)
                }
                .listStyle(.plain)
                .onAppear { model.scroller = { proxy.scrollTo($0, anchor: .top) } }
            }
            .imagePipeline(model.pipeline)
        case .stack:
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<model.rowCount, id: \.self) { row in
                            VStack(spacing: 0) {
                                LazyImageReuseCell(row: row, style: .row, model: model)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                Divider()
                                    .padding(.leading, 84)
                            }
                        }
                    }
                }
                .onAppear { model.scroller = { proxy.scrollTo($0, anchor: .top) } }
            }
            .imagePipeline(model.pipeline)
        case .grid:
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 2)], spacing: 2) {
                        ForEach(0..<model.rowCount, id: \.self) { row in
                            LazyImageReuseCell(row: row, style: .tile, model: model)
                        }
                    }
                }
                .onAppear { model.scroller = { proxy.scrollTo($0, anchor: .top) } }
            }
            .imagePipeline(model.pipeline)
        case .collectionView:
            ViewControllerView { [model] in
                LazyImageReuseViewController(model: model)
            }
        }
    }

    private static let info = DemoInfo(
        "LazyImage Reuse",
        "`LazyImage` draws an image that is in the memory cache in the first body for its request, with no placeholder before it. The screen counts every body and calls one that draws a placeholder, a failure, or another request's image while the memory cache has the image **stale**. There should be none.",
        code: """
        List(rows) { row in
            LazyImage(request: row.request) { state in
                if let image = state.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.gray
                }
            }
            .onDisappear(.cancel)
        }
        .imagePipeline(pipeline)
        """,
        points: [
            .init("Scroll Back", "**Run** does it in the current container: a latency of 1 s and an empty memory cache, a jump 120 rows down while the top rows are loading, which cancels them, **Prefetch**, and a jump back. The run line counts the stale bodies and the hits, with their rows, and the loads started from the jump on. By hand: fling the list, prefetch, and scroll back."),
            .init("Stale", "A stale body is a render that has to be done again, and a flash if its frame reaches the screen. Most of them are off screen: a row cancelled on its way out draws again while it's away, and a `List` row that comes back shows what it drew last, without running its body before `onAppear`."),
            .init("Prefetch", "Puts every row's image in the memory cache with `ImagePrefetcher`, on a pipeline of its own over the same cache and with no latency, so that it takes a second rather than a minute."),
            .init("Reuse", "**UIKit** hosts `LazyImage` in `UICollectionView` cells with `UIHostingConfiguration`. A reused cell keeps its `LazyImage` and gets a new request, which it draws from the memory cache in the same body rather than the image of the row it showed before."),
            .init("Eviction", "With the memory cache at 30 images, scroll far and back. The cells whose images were evicted show a placeholder and load again, from the fixture loader: that isn't stale, because the cache didn't have them."),
            .init("Request Changes", "**Requests** switches every cell between the original and a 64 pt thumbnail, and **Latency** builds a new pipeline over the same memory cache. Either changes what every visible cell loads; once both variants are loaded, neither draws a placeholder."),
            .init("Counters", "**hit** is a body that drew the image from the memory cache ahead of its load, **starts** the loads that started a task, and the completions are split by where the image came from. The HUD shows the memory cache lookups, including the ones `LazyImage` makes in its body.")
        ]
    )
}

// MARK: - Model

@MainActor @Observable
private final class LazyImageReuseModel {
    enum Container: String, CaseIterable, Identifiable {
        case list = "List"
        case stack = "Stack"
        case grid = "Grid"
        case collectionView = "UIKit"

        var id: Self { self }
    }

    enum Latency: String, CaseIterable, Identifiable {
        case none = "None"
        case short = "300 ms"
        case long = "1 s"
        case veryLong = "3 s"

        var id: Self { self }

        var duration: Duration {
            switch self {
            case .none: .zero
            case .short: .milliseconds(300)
            case .long: .seconds(1)
            case .veryLong: .seconds(3)
            }
        }
    }

    enum Disappear: String, CaseIterable, Identifiable {
        case cancel = "Cancel"
        case lowerPriority = "Lower Priority"
        case nothing = "Nothing"

        var id: Self { self }
    }

    enum CacheLimit: String, CaseIterable, Identifiable {
        case unlimited = "Unlimited"
        case hundred = "100 Images"
        case thirty = "30 Images"

        var id: Self { self }

        var countLimit: Int {
            switch self {
            case .unlimited: .max
            case .hundred: 100
            case .thirty: 30
            }
        }
    }

    enum Variant: String, CaseIterable, Identifiable {
        case original = "Original"
        case thumbnail = "64 pt Thumbnail"

        var id: Self { self }
    }

    var container = Container.list
    var latency = Latency.short {
        didSet { pipeline = Self.makePipeline(latency: latency, imageCache: imageCache) }
    }
    var disappear = Disappear.cancel
    var cacheLimit = CacheLimit.unlimited {
        didSet { imageCache.countLimit = cacheLimit.countLimit }
    }
    var variant = Variant.original
    /// Changed to build every cell again, with new state.
    private(set) var generation = 0
    private(set) var pipeline: ImagePipeline
    private(set) var isRunning = false
    private(set) var lastRun: String?

    /// Scrolls the container on screen to put a row at the top.
    @ObservationIgnored var scroller: ((Int) -> Void)?

    let rowCount = 300
    /// Shared by the pipelines of every latency, so that a new one starts
    /// with what the last one cached.
    let imageCache: ImageCache
    let tally = LazyImageReuseTally()

    /// A URL of its own for every row, so that each has a cache key of its
    /// own. The fixture loader ignores the query.
    private let urls: [URL]
    @ObservationIgnored private var prefetcher: ImagePrefetcher?

    init() {
        let photos = DemoFixture.photos
        urls = (0..<rowCount).map { row in
            photos[row % photos.count].url.appending(queryItems: [URLQueryItem(name: "row", value: "\(row)")])
        }
        let imageCache = ImageCache()
        self.imageCache = imageCache
        pipeline = Self.makePipeline(latency: .short, imageCache: imageCache)
    }

    func request(for row: Int) -> ImageRequest {
        switch variant {
        case .original:
            ImageRequest(url: urls[row])
        case .thumbnail:
            ImageRequest(url: urls[row], processors: [.resize(size: CGSize(width: 64, height: 64), crop: true)])
        }
    }

    /// Loads every row's image into the memory cache, on a pipeline of its
    /// own over the same cache and with no latency.
    func prefetchAll() {
        _ = startPrefetching()
    }

    /// Scrolls the top rows away while they load, fills the memory cache, and
    /// scrolls back: the scroll-back of a list with a prefetcher.
    func runScrollBack() async {
        guard !isRunning, scroller != nil else { return }
        isRunning = true
        defer { isRunning = false }

        latency = .long
        cacheLimit = .unlimited
        clearMemoryCache()
        scroller?(0)
        // The top rows start loads that take a second.
        await pause(.milliseconds(400))
        tally.reset()
        scroller?(120)
        await pause(.milliseconds(400))
        await withCheckedContinuation { continuation in
            startPrefetching().didComplete = { continuation.resume() }
        }
        scroller?(0)
        await pause(.milliseconds(600))
        lastRun = "last run · \(tally.stale) stale\(Self.rows(tally.staleRows)) · \(tally.hits) hits\(Self.rows(tally.hitRows)) · \(tally.starts) starts"
    }

    private func startPrefetching() -> ImagePrefetcher {
        let pipeline = Self.makePipeline(latency: .none, imageCache: imageCache, label: "LazyImage Reuse Prefetch")
        let prefetcher = ImagePrefetcher(pipeline: pipeline, destination: .memoryCache, maxConcurrentRequestCount: 6)
        prefetcher.startPrefetching(with: (0..<rowCount).map(request(for:)))
        self.prefetcher = prefetcher
        return prefetcher
    }

    /// " in rows 0–6", or nothing for no rows.
    private static func rows(_ rows: IndexSet) -> String {
        guard let first = rows.first, let last = rows.last else { return "" }
        return first == last ? " in row \(first)" : " in rows \(first)–\(last)"
    }

    private func pause(_ duration: Duration) async {
        try? await Task.sleep(for: duration)
    }

    func clearMemoryCache() {
        prefetcher = nil
        imageCache.removeAll()
    }

    func rebuild() {
        generation += 1
    }

    private static func makePipeline(latency: Latency, imageCache: ImageCache, label: String = "LazyImage Reuse") -> ImagePipeline {
        var configuration = ImagePipeline.Configuration()
        configuration.dataLoader = DemoFixtureLoader(pace: .init(latency: latency.duration))
        configuration.imageCache = imageCache
        return DemoPipelineProbe.makePipeline(label, configuration: configuration)
    }
}

/// What the cells drew. Not observed: the cells write it from their bodies,
/// and the header reads it on a timer.
@MainActor
private final class LazyImageReuseTally {
    private(set) var bodies = 0
    private(set) var hits = 0
    private(set) var stale = 0
    private(set) var starts = 0
    private(set) var completions: [LazyImageReuseStatus: Int] = [:]
    /// The rows that drew a hit.
    private(set) var hitRows = IndexSet()
    private var staleByRow: [Int: Int] = [:]

    /// The rows that drew a stale body.
    var staleRows: IndexSet {
        IndexSet(staleByRow.keys)
    }

    /// Records a body of the cell and returns what it shows.
    func record(_ state: any LazyImageState, row: Int, key: ImageCacheKey, isCached: Bool) -> LazyImageReuseStatus {
        let status = LazyImageReuseStatus(state)
        bodies += 1
        if status == .hit {
            hits += 1
            hitRows.insert(row)
        }
        if isCached && !state.isLoading && !Self.isShowingImage(of: key, state) {
            stale += 1
            staleByRow[row, default: 0] += 1
        }
        return status
    }

    func recordStart() {
        starts += 1
    }

    func record(_ result: Result<ImageResponse, ImagePipeline.Error>) {
        let status: LazyImageReuseStatus = switch result {
        case .success(let response): .init(response)
        case .failure: .failed
        }
        completions[status, default: 0] += 1
    }

    func stale(row: Int) -> Int {
        staleByRow[row] ?? 0
    }

    func reset() {
        bodies = 0
        hits = 0
        stale = 0
        starts = 0
        completions = [:]
        hitRows = IndexSet()
        staleByRow = [:]
    }

    private static func isShowingImage(of key: ImageCacheKey, _ state: any LazyImageState) -> Bool {
        guard state.image != nil else { return false }
        guard case .success(let response)? = state.result else { return true }
        return ImageCacheKey(request: response.request) == key
    }
}

/// What a cell shows.
private enum LazyImageReuseStatus: Hashable {
    /// The image `LazyImage` drew from the memory cache ahead of its load.
    case hit
    case loading
    case memory
    case disk
    case network
    case failed
    /// Nothing loaded: before the first load, or a cancelled one.
    case idle

    @MainActor
    init(_ state: any LazyImageState) {
        if !(state is FetchImage) {
            self = .hit
        } else if state.isLoading {
            self = .loading
        } else {
            switch state.result {
            case .success(let response)?: self.init(response)
            case .failure?: self = .failed
            case nil: self = .idle
            }
        }
    }

    init(_ response: ImageResponse) {
        switch response.cacheType {
        case .memory: self = .memory
        case .disk: self = .disk
        case nil: self = .network
        }
    }

    var text: String {
        switch self {
        case .hit: "hit"
        case .loading: "loading"
        case .memory: "memory"
        case .disk: "disk"
        case .network: "loaded"
        case .failed: "failed"
        case .idle: "idle"
        }
    }

    var color: Color {
        switch self {
        case .hit: .green
        case .loading: .orange
        case .memory: .blue
        case .disk: .purple
        case .network: .secondary
        case .failed: .red
        case .idle: .gray
        }
    }
}

// MARK: - Header

private struct LazyImageReuseHeader: View {
    @Bindable var model: LazyImageReuseModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Container", selection: $model.container) {
                ForEach(LazyImageReuseModel.Container.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Button("Run", systemImage: "play.fill") {
                    Task { await model.runScrollBack() }
                }
                .disabled(model.isRunning)
                Button("Prefetch", systemImage: "square.and.arrow.down") { model.prefetchAll() }
                Button("Clear Cache", systemImage: "trash") { model.clearMemoryCache() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .labelStyle(.titleAndIcon)

            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let tally = model.tally
                VStack(alignment: .leading, spacing: 2) {
                    DemoMonoLabel("\(tally.stale) stale · \(tally.hits) hits · \(tally.bodies) bodies", tint: tally.stale > 0 ? .red : .primary)
                    DemoMonoLabel("\(tally.starts) starts · done \(completions(tally))")
                    DemoMonoLabel("memory cache \(model.imageCache.totalCount) · \(model.latency.rawValue) · \(model.disappear.rawValue.lowercased()) on disappear")
                    DemoMonoLabel(model.isRunning ? "running…" : model.lastRun ?? "last run · –", tint: .primary)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func completions(_ tally: LazyImageReuseTally) -> String {
        let order: [LazyImageReuseStatus] = [.memory, .disk, .network, .failed]
        let parts = order.compactMap { status in
            tally.completions[status].map { "\($0) \(status.text)" }
        }
        return parts.isEmpty ? "–" : parts.joined(separator: ", ")
    }
}

private struct LazyImageReuseOptions: View {
    @Bindable var model: LazyImageReuseModel

    var body: some View {
        Menu("Options", systemImage: "slider.horizontal.3") {
            Picker("Latency", selection: $model.latency) {
                ForEach(LazyImageReuseModel.Latency.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("On Disappear", selection: $model.disappear) {
                ForEach(LazyImageReuseModel.Disappear.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Memory Cache", selection: $model.cacheLimit) {
                ForEach(LazyImageReuseModel.CacheLimit.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Requests", selection: $model.variant) {
                ForEach(LazyImageReuseModel.Variant.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            Divider()
            Button("Rebuild Cells", systemImage: "arrow.clockwise") { model.rebuild() }
            Button("Reset Counters", systemImage: "gobackward") { model.tally.reset() }
        }
    }
}

// MARK: - Cell

private struct LazyImageReuseCell: View {
    enum Style {
        case row
        case tile
    }

    let row: Int
    let style: Style
    let model: LazyImageReuseModel

    var body: some View {
        let request = model.request(for: row)
        let key = ImageCacheKey(request: request)
        let imageCache = model.imageCache
        let tally = model.tally
        let row = row
        let style = style
        LazyImage(request: request) { state in
            // The cache itself, not the pipeline's, which the HUD counts.
            let isCached = imageCache[key].map { !$0.isPreview } ?? false
            let status = tally.record(state, row: row, key: key, isCached: isCached)
            LazyImageReuseCellContent(
                row: row,
                style: style,
                image: state.image,
                status: status,
                stale: tally.stale(row: row)
            )
        }
        .demoOnDisappear(model.disappear)
        .onStart { _ in tally.recordStart() }
        .onCompletion { tally.record($0) }
    }
}

private extension LazyImage {
    func demoOnDisappear(_ disappear: LazyImageReuseModel.Disappear) -> Self {
        switch disappear {
        case .cancel: onDisappear(.cancel)
        case .lowerPriority: onDisappear(.lowerPriority)
        case .nothing: onDisappear(nil)
        }
    }
}

private struct LazyImageReuseCellContent: View {
    let row: Int
    let style: LazyImageReuseCell.Style
    let image: Image?
    let status: LazyImageReuseStatus
    let stale: Int

    var body: some View {
        switch style {
        case .row:
            HStack(spacing: 12) {
                thumbnail
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Row \(row)")
                        .font(.subheadline.weight(.medium))
                    DemoMonoLabel(status.text, tint: status.color)
                }
                Spacer(minLength: 0)
                if stale > 0 {
                    DemoBadge("\(stale) stale", color: .red)
                }
            }
        case .tile:
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { thumbnail }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    DemoBadge("\(row) \(status.text)", color: status.color, style: .overImage)
                        .padding(4)
                }
                .overlay(alignment: .topTrailing) {
                    if stale > 0 {
                        DemoBadge("\(stale)", color: .red, style: .overImage)
                            .padding(4)
                    }
                }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            image
                .resizable()
                .scaledToFill()
        } else if status == .failed {
            Color.red.opacity(0.25)
        } else {
            Color(.secondarySystemBackground)
        }
    }
}

// MARK: - UIKit

/// `LazyImage` in `UICollectionView` cells, hosted with
/// `UIHostingConfiguration`. A reused cell keeps its `LazyImage`, and with it
/// the view model, and gets the request of another row.
private final class LazyImageReuseViewController: UICollectionViewController {
    private let model: LazyImageReuseModel

    init(model: LazyImageReuseModel) {
        self.model = model
        let layout = UICollectionViewCompositionalLayout.list(using: UICollectionLayoutListConfiguration(appearance: .plain))
        super.init(collectionViewLayout: layout)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: "cell")
        model.scroller = { [weak self] row in
            self?.collectionView.scrollToItem(at: IndexPath(item: row, section: 0), at: .top, animated: false)
        }
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        model.rowCount
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        let model = model
        let row = indexPath.item
        cell.contentConfiguration = UIHostingConfiguration {
            LazyImageReuseHostedCell(row: row, model: model)
        }
        return cell
    }
}

/// Reads the pipeline in a body of its own: the content of a hosting
/// configuration is made once, and the pipeline changes with the latency.
private struct LazyImageReuseHostedCell: View {
    let row: Int
    let model: LazyImageReuseModel

    var body: some View {
        LazyImageReuseCell(row: row, style: .row, model: model)
            .imagePipeline(model.pipeline)
    }
}
