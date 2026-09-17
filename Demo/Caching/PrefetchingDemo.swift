// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI
import UIKit

/// Demonstrates ``ImagePrefetcher`` in UIKit and in SwiftUI, with its two
/// destinations, its priority, and a count of what it had ready in time.
///
/// ```swift
/// prefetcher.startPrefetching(with: urls)
/// prefetcher.stopPrefetching(with: urls)
/// ```
///
/// The count is what the screen is for: of the images the grid asked for,
/// how many were already in the memory cache, checked the moment a cell
/// asks. The screen has a pipeline of its own, "Prefetching", with a
/// `DataCache` for the disk destination to fill, and a change of any
/// setting empties both caches and starts over. An image in the memory cache
/// can then only have been put there by the prefetcher.
struct PrefetchingDemo: View {
    @StateObject private var model = PrefetchingDemoModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Picker("Kind", selection: $model.kind) {
                    ForEach(PrefetchingDemoModel.Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                PrefetchSettingsView(model: model)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Group {
                switch model.kind {
                case .uikit:
                    ViewControllerView { [model] in PrefetchingViewController(model: model) }
                case .swiftUI:
                    SwiftUIPrefetchingGrid(model: model, prefetcher: model.gridPrefetcher)
                }
            }
            // A new grid for every start: it scrolls to the top and asks
            // for its first cells again.
            .id(model.generation)

            PrefetchReadoutView(model: model)
        }
        .toolbar {
            Button {
                model.restart()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Start Over")
        }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Prefetching",
        "`ImagePrefetcher` loads images before they appear on screen. It runs its requests at a low priority and only a few at a time, so it never gets in the way of the images the user is looking at. The count under the grid says how many images it had ready when a cell asked for one.",
        code: """
        let prefetcher = ImagePrefetcher(
            destination: .memoryCache
        )
        prefetcher.priority = .low

        prefetcher.startPrefetching(with: urls)
        prefetcher.stopPrefetching(with: urls)
        """,
        points: [
            .init("Same request", "Prefetch with the request you display with. If they differ by so much as a processor, the prefetcher fills the cache with images you never show."),
            .init("UIKit", "`UICollectionViewDataSourcePrefetching` tells you exactly which items to start and which ones to stop."),
            .init("SwiftUI", "There is no equivalent, so the demo derives the window from `onAppear` and `onDisappear`."),
            .init("Destination", "`.memoryCache`, the default, decodes each image and stores it in both caches, so a cell finds it ready to draw. `.diskCache` only downloads the data and stores it on disk: no decoding, less CPU and memory, but a cell still decodes the image when it asks. It needs a `DataCache` and a policy that stores the original data. The destination is fixed when the prefetcher is made, so changing it here makes a new prefetcher and starts over."),
            .init("Priority", "`priority` is `.low` by default, below the cells on screen, and applies to the outstanding requests when it changes. Work created below `.normal` waits newest-first in Nuke's queues today, so at `.low` a batch starts with its first two requests and then works back from its far end: the order line under the grid shows it. At `.normal` and above, a batch starts in order. Priority & Coalescing, linked from the priority menu, shows what a priority does in the data loading queue."),
            .init("The count", "Each cell is counted once, when it first asks for its image – a collection view asks a little before the cell is on screen. It counts as in memory if the memory cache has the image right then, and as on disk if the disk cache has its data. The screen starts with both caches empty, so only the prefetcher can have put an image there."),
            .init("Pausing", "`isPaused` holds the queue when the screen goes away. The outstanding requests finish and the rest wait, so coming back is instant."),
            .init("Its own pipeline", "The screen has a pipeline with a `DataCache`, so `.diskCache` has a disk to fill. The button in the toolbar empties both caches and starts over with the same settings.")
        ]
    )
}

// MARK: - Settings and Readout

private struct PrefetchSettingsView: View {
    @ObservedObject var model: PrefetchingDemoModel

    @Environment(\.demoOpen) private var open

    var body: some View {
        HStack(spacing: 20) {
            Menu {
                Picker("Destination", selection: $model.destination) {
                    ForEach(PrefetchingDemoModel.destinations, id: \.self) { Text($0.demoName).tag($0) }
                }
            } label: {
                SettingLabel(title: "destination", value: model.destination.demoName)
            }

            Menu {
                Picker("Priority", selection: $model.priority) {
                    ForEach(ImageRequest.Priority.demoAllCases, id: \.self) { Text($0.demoName).tag($0) }
                }
                if let open {
                    Section {
                        Button {
                            open(.screen(.priorityAndCoalescing))
                        } label: {
                            Label(DemoScreen.priorityAndCoalescing.title, systemImage: "arrow.forward")
                        }
                    }
                }
            } label: {
                SettingLabel(title: "priority", value: model.priority.demoName)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct SettingLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
        }
        .font(.system(.caption, design: .monospaced))
        .lineLimit(1)
    }
}

/// The count, and what the prefetcher was last asked and did.
private struct PrefetchReadoutView: View {
    @ObservedObject var model: PrefetchingDemoModel

    var body: some View {
        let tally = model.tally
        VStack(alignment: .leading, spacing: 2) {
            Text(tally.headline)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            DemoMonoLabel(tally.detail)
            DemoMonoLabel(model.activity)
            DemoMonoLabel(model.downloadOrder)
                .truncationMode(.head)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - UIKit

/// Uses `UICollectionViewDataSourcePrefetching`, which tells you exactly which
/// items to prefetch and which ones are no longer needed.
private final class PrefetchingViewController: PhotoGridViewController, UICollectionViewDataSourcePrefetching {
    private let model: PrefetchingDemoModel
    /// The prefetcher of the start the grid belongs to, which the model has
    /// replaced by the time a replaced grid goes away.
    private let prefetcher: ImagePrefetcher

    init(model: PrefetchingDemoModel) {
        self.model = model
        self.prefetcher = model.prefetcher
        super.init()
        photos = model.photos
        pipeline = model.pipeline
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView.isPrefetchingEnabled = true
        collectionView.prefetchDataSource = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        prefetcher.isPaused = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // The prefetcher finishes the outstanding requests and holds the rest,
        // so the work resumes instantly when the user comes back.
        prefetcher.isPaused = true
    }

    override func makeLoadingOptions() -> ImageLoadingOptions {
        // A failed cell says so rather than staying as gray as a loading one.
        var options = super.makeLoadingOptions()
        options.failureImage = UIImage(systemName: "exclamationmark.triangle")
        options.contentModes = .init(success: .scaleAspectFill, failure: .center, placeholder: .scaleAspectFill)
        options.tintColors = .init(success: nil, failure: .secondaryLabel, placeholder: nil)
        return options
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        // Before the cell starts its own request.
        model.willShow(indexPath.item)
        return super.collectionView(collectionView, cellForItemAt: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        model.startPrefetching(indexPaths.map(\.item), with: prefetcher)
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        model.stopPrefetching(indexPaths.map(\.item), with: prefetcher)
    }
}

// MARK: - SwiftUI

private struct SwiftUIPrefetchingGrid: View {
    @ObservedObject var model: PrefetchingDemoModel
    /// The one of the start the grid belongs to; see
    /// `PrefetchingViewController.prefetcher`.
    let prefetcher: GridPrefetcher

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(model.photos.enumerated()), id: \.offset) { index, url in
                    SquareCell {
                        LazyImage(url: url) { state in
                            if let image = state.image {
                                image.resizable().scaledToFill()
                            } else if state.error != nil {
                                DemoFailureView()
                            } else {
                                Color(.secondarySystemBackground)
                            }
                        }
                        .pipeline(model.pipeline)
                    }
                    .onAppear {
                        model.willShow(index)
                        prefetcher.onAppear(index)
                    }
                    .onDisappear { prefetcher.onDisappear(index) }
                }
            }
        }
        .onDisappear { prefetcher.isPaused = true }
        .onAppear { prefetcher.isPaused = false }
    }
}

// MARK: - Model

@MainActor
private final class PrefetchingDemoModel: ObservableObject {
    enum Kind: String, CaseIterable, Identifiable {
        case uikit = "UIKit"
        case swiftUI = "SwiftUI"

        var id: Self { self }
    }

    /// What the grid asked for since the last start.
    struct Tally {
        /// The cells that asked for an image, each counted once.
        var shown = 0
        /// Of those, the ones whose image was in the memory cache.
        var inMemory = 0
        /// The ones whose data was on disk, but not the image in memory.
        var onDisk = 0
        /// The images the prefetcher was asked for.
        var requested = 0

        var headline: String {
            shown == 0 ? "Nothing shown yet" : "\(inMemory) of \(shown) shown were in memory"
        }

        var detail: String {
            "\(onDisk) on disk · \(shown - inMemory - onDisk) not ready · \(requested) prefetched"
        }
    }

    static let destinations: [ImagePrefetcher.Destination] = [.memoryCache, .diskCache]

    @Published var kind: Kind = .uikit {
        didSet { restart() }
    }

    @Published var destination: ImagePrefetcher.Destination = .memoryCache {
        didSet { restart() }
    }

    @Published var priority: ImageRequest.Priority = .low {
        didSet {
            // Live: the outstanding requests take it too.
            prefetcher.priority = priority
            activity = "priority \(priority.demoName)"
        }
    }

    @Published private(set) var generation = 0
    @Published private(set) var tally = Tally()
    @Published private(set) var activity = PrefetchingDemoModel.idleActivity
    /// The downloads the prefetcher started, in the order it started them.
    @Published private(set) var downloads: [Int] = []

    let photos: [URL]
    let pipeline: ImagePipeline
    private(set) var prefetcher: ImagePrefetcher
    private(set) var gridPrefetcher: GridPrefetcher

    /// The prefetcher's requests: the grid's, with a label that tells their
    /// downloads apart and the start they belong to. Neither the caches nor
    /// the prefetcher key on `userInfo`, so they still match the grid's.
    private var requests: [ImageRequest]
    private var shownIndices: Set<Int> = []
    private let indices: [URL: Int]

    private static let idleActivity = "Scroll to see the prefetcher at work"

    init() {
        let photos = DemoImages.photos
        self.photos = photos
        self.indices = Dictionary(photos.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        var configuration = ImagePipeline.Configuration.withDataCache(name: "com.github.kean.NukeDemo.Prefetching")
        configuration.imageCache = ImageCache()
        configuration.dataCache?.removeAll()

        // The probe reports every download the pipeline starts, with the
        // request that started it, on the pipeline's threads.
        let relay = DemoRelay<PrefetchingDemoModel>()
        self.pipeline = DemoPipelineProbe.makePipeline("Prefetching", configuration: configuration, onEvent: { event in
            guard case .willLoadData = event.kind,
                  event.request.userInfo[.labelKey] as? String == Self.label,
                  let url = event.request.url,
                  let generation = event.request.userInfo[.generationKey] as? Int else {
                return
            }
            Task { @MainActor in relay.model?.didStartDownload(url, generation: generation) }
        })

        let requests = Self.makeRequests(photos, generation: 0)
        let prefetcher = ImagePrefetcher(pipeline: pipeline)
        self.requests = requests
        self.prefetcher = prefetcher
        self.gridPrefetcher = GridPrefetcher(prefetcher: prefetcher, requests: requests)
        relay.model = self
        observeGridPrefetcher()
    }

    // MARK: Starting Over

    /// Drops the prefetcher and what it did: a new one with the current
    /// settings, both caches emptied, and a new grid.
    func restart() {
        prefetcher.stopPrefetching()
        generation += 1
        requests = Self.makeRequests(photos, generation: generation)
        prefetcher = ImagePrefetcher(pipeline: pipeline, destination: destination)
        prefetcher.priority = priority
        gridPrefetcher = GridPrefetcher(prefetcher: prefetcher, requests: requests)
        observeGridPrefetcher()
        pipeline.cache.removeAll()
        shownIndices.removeAll()
        tally = Tally()
        downloads.removeAll()
        activity = Self.idleActivity
    }

    // MARK: The Grid

    /// Counts a cell the first time it asks for its image.
    func willShow(_ index: Int) {
        guard shownIndices.insert(index).inserted, requests.indices.contains(index) else { return }
        let request = requests[index]
        tally.shown += 1
        if isInMemory(request) {
            tally.inMemory += 1
        } else if isOnDisk(request) {
            tally.onDisk += 1
        }
    }

    func startPrefetching(_ indices: [Int], with prefetcher: ImagePrefetcher) {
        guard prefetcher === self.prefetcher else { return }
        prefetcher.startPrefetching(with: indices.map { requests[$0] })
        didChangeWindow(started: indices, stopped: [])
    }

    func stopPrefetching(_ indices: [Int], with prefetcher: ImagePrefetcher) {
        guard prefetcher === self.prefetcher else { return }
        prefetcher.stopPrefetching(with: indices.map { requests[$0] })
        didChangeWindow(started: [], stopped: indices)
    }

    private func observeGridPrefetcher() {
        gridPrefetcher.onChange = { [weak self] started, stopped in
            self?.didChangeWindow(started: started, stopped: stopped)
        }
    }

    private func didChangeWindow(started: [Int], stopped: [Int]) {
        tally.requested += started.count
        var parts: [String] = []
        if !started.isEmpty {
            parts.append("start \(Self.ranges(started))")
        }
        if !stopped.isEmpty {
            parts.append("stop \(Self.ranges(stopped))")
        }
        if !parts.isEmpty {
            activity = parts.joined(separator: " · ")
        }
    }

    fileprivate func didStartDownload(_ url: URL, generation: Int) {
        guard generation == self.generation, let index = indices[url] else { return }
        downloads.append(index)
    }

    /// "downloads 28 29 55 54 53 …", newest last.
    var downloadOrder: String {
        guard !downloads.isEmpty else {
            return "no prefetch downloads yet"
        }
        return "downloads " + downloads.suffix(40).map(String.init).joined(separator: " ")
    }

    // MARK: The Caches

    /// Reads the configuration's `ImageCache` itself: a main-thread read
    /// through `pipeline.cache` would count as a view's cache hit in the
    /// probe, and the HUD would show hits nobody displayed.
    private func isInMemory(_ request: ImageRequest) -> Bool {
        guard let container = pipeline.configuration.imageCache?[pipeline.cache.makeImageCacheKey(for: request)] else {
            return false
        }
        return !container.isPreview
    }

    private func isOnDisk(_ request: ImageRequest) -> Bool {
        pipeline.configuration.dataCache?.containsData(for: pipeline.cache.makeDataCacheKey(for: request)) ?? false
    }

    // MARK: Helpers

    /// The `labelKey` of the prefetcher's requests.
    nonisolated fileprivate static let label = "prefetch"

    private static func makeRequests(_ photos: [URL], generation: Int) -> [ImageRequest] {
        photos.map { url in
            var request = ImageRequest(url: url)
            request.userInfo[.labelKey] = label
            request.userInfo[.generationKey] = generation
            return request
        }
    }

    /// "0–3, 8, 10–12".
    private static func ranges(_ indices: [Int]) -> String {
        var runs: [ClosedRange<Int>] = []
        for index in Set(indices).sorted() {
            if let last = runs.last, index == last.upperBound + 1 {
                runs[runs.count - 1] = last.lowerBound...index
            } else {
                runs.append(index...index)
            }
        }
        return runs
            .map { $0.count == 1 ? "\($0.lowerBound)" : "\($0.lowerBound)–\($0.upperBound)" }
            .joined(separator: ", ")
    }
}

extension ImageRequest.UserInfoKey {
    /// The start of the Prefetching screen a prefetch belongs to.
    fileprivate static let generationKey: ImageRequest.UserInfoKey = "com.github.kean.NukeDemo.Prefetching.generation"
}

extension ImagePrefetcher.Destination {
    fileprivate var demoName: String {
        switch self {
        case .memoryCache: ".memoryCache"
        case .diskCache: ".diskCache"
        }
    }
}
