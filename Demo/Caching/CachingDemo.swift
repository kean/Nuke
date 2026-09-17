// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import SwiftUI
import UniformTypeIdentifiers

/// Demonstrates the cache layers – the memory cache, the HTTP disk cache
/// (`URLCache`), and the pipeline's own disk cache (``DataCache``) – and what
/// each ``ImagePipeline/DataCachePolicy`` keeps in the last one.
///
/// ```swift
/// var configuration = ImagePipeline.Configuration.withDataCache(name: "images")
/// configuration.dataCachePolicy = .automatic
/// ImagePipeline.shared = ImagePipeline(configuration: configuration)
/// ```
///
/// Three requests load together: one image as it is, a second one resized, and
/// a third as a thumbnail. They are three different images, so a policy that
/// keeps the downloaded data of one request and not of another shows it. The
/// list works out the file of every key the requests read and write under –
/// `DataCache` doesn't list its entries – and says which write put it there,
/// from the `willCache` events of the demo's pipeline probe.
///
/// The policy is part of the configuration, so picking one builds a new
/// pipeline, with a disk cache of its own that is emptied first. The pipelines
/// record diagnostics, which is how a tile knows which key the disk answered.
struct CachingDemo: View {
    @StateObject private var model = CachingDemoModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        // The images above the caches on a phone held upright, beside them
        // everywhere else, so that they stay in view while the list scrolls.
        let isStacked = horizontalSizeClass == .compact && verticalSizeClass != .compact
        let layout = isStacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        let stage = CachingStage(model: model)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        layout {
            if isStacked {
                stage
            } else {
                ScrollView {
                    stage
                }
            }
            Divider()
            CachingPanel(model: model)
                .frame(maxWidth: isStacked ? .infinity : 400)
        }
        .background(Color(.systemGroupedBackground))
        .task { model.startIfNeeded() }
        .onDisappear { model.cancel() }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Caching",
        "Nuke keeps decoded images in memory and data on disk. The disk is either `URLCache`, which keeps what the server sent, or the pipeline's own `DataCache`, where the `DataCachePolicy` decides what goes in: the downloaded data, the images the pipeline made from it, or both. The three requests on this screen load into empty caches, and the lists show what each layer kept, and under which key.",
        code: """
        var configuration = ImagePipeline.Configuration
            .withDataCache(name: "images")
        configuration.dataCachePolicy = .automatic
        let pipeline = ImagePipeline(configuration: configuration)

        let key = pipeline.cache.makeDataCacheKey(for: request)
        let image = pipeline.cache.cachedImage(for: request)
        """,
        points: [
            .init("Try it", "Pick a policy: the three requests download into an empty disk cache, and On Disk shows the files they left. Clear the memory cache and Load again: the disk answers, and each tile says whether it found its own image or made it again from the downloaded data. Try the other policies and compare the counts beside them."),
            .init("The four policies", "`.storeOriginalData`, the default, keeps only the downloaded data, so a resize or a thumbnail is made again after every memory miss. `.storeEncodedImages` keeps only images, each encoded after it was decoded, the unprocessed one included. `.automatic` keeps the downloaded data of a request with no processors, and the encoded image of one with processors or a thumbnail. `.storeAll` keeps the downloaded data of every request, and the encoded image of a processed one too."),
            .init("Thumbnails under .automatic", "A thumbnail request has no processors, so `.automatic` keeps its downloaded data. It keeps the encoded thumbnail as well, because a thumbnail counts as processed for that decision, so the PNG's request leaves two files."),
            .init("Encoded images", "The pipeline encodes an image once it is decoded, processed, and decompressed, one at a time on its encoding queue, then hands the data to the delegate's `willCache` and stores it. The default encoder writes a JPEG at 0.8 quality, or a PNG for an image with transparency, so an encoded image isn't always smaller than the file it came from: the PNG's thumbnail can take more room than the PNG. Under `.storeEncodedImages`, the unprocessed request reads back what the pipeline encoded rather than the server's bytes, and for the photo that is a larger file."),
            .init("disableDiskCacheWrites", "The option keeps the downloaded data off the disk, but not an encoded image: the pipeline writes those without checking it. Turn it on and pick each policy. Anything On Disk in orange is a write the option didn't stop, and `.storeOriginalData` is the only policy that leaves the disk empty. The direct `storeCachedImage` and `storeCachedData` do check it."),
            .init("A new pipeline", "The policy is a property of `ImagePipeline.Configuration`, which a pipeline takes when it is created, so each pick builds a new pipeline. Each policy has a disk cache directory of its own, emptied when its pipeline is built, so every pick starts clean. The switch is a request option and needs no new pipeline, but it builds one too, so that the counts under the images start over with it."),
            .init("URLCache", "The default configuration. `URLSession` keeps one response per URL, as the server sent it, and honors its cache-control headers. The pipeline never writes to it, so the resize and the thumbnail are made again from the response after a memory miss, and `ImagePipeline.Cache` can't read or empty it. Offline, the demo's fixtures don't go through `URLSession`, so `URLCache` stays empty."),
            .init("Memory cache", "`ImageCache` holds the decoded image each request ended with, keyed by the request's image ID, scale, thumbnail, and processors, so the three requests take three entries. It is an LRU cache with a cost limit, and it empties itself when memory runs low. A hit on the disk still costs a decode."),
            .init("Direct access", "`pipeline.cache` reads and writes the entries the pipeline does, under the keys `makeImageCacheKey(for:)` and `makeDataCacheKey(for:)` return, and a `DataCache` names each file after the SHA-1 of its key. A read from the disk is a file read, and for an image a decode too, so the screen makes every call off the main thread. A direct store doesn't go through the delegate's `willCache`: the HUD counts the encode of `storeCachedImage`, but no disk write."),
            .init("The images", "A 310 KB JPEG photo, a 173 KB WebP of a tree, and an 18 KB PNG with transparency, from user-images.githubusercontent.com and kean.blog. The resize and the thumbnail both fit the image in 160 × 160 pt. Offline, fixtures in the same formats stand in for them.")
        ]
    )
}

// MARK: - Stage

/// The three images, where each came from, and what the pipeline has done.
private struct CachingStage: View {
    @ObservedObject var model: CachingDemoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(CachingDemoModel.Item.allCases) { item in
                    TileView(item: item, tile: model.tiles[item] ?? .init())
                }
            }
            .frame(maxWidth: 480)
            actions
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.counts.indices, id: \.self) { index in
                    DemoMonoLabel(model.counts[index])
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let mismatch = model.mismatch {
                    DemoMonoLabel(mismatch.text, tint: mismatch.isProblem ? .orange : .green)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Load", systemImage: "arrow.clockwise") { model.load() }
            // Clearing doesn't load: it sets up where the next load finds the
            // images.
            Menu("Clear") {
                Button("Memory Cache") { model.clear([.memory]) }
                Button("Disk Cache") { model.clear([.disk]) }
                Button("Both", role: .destructive) { model.clear([.all]) }
            }
            Spacer(minLength: 8)
            DemoMonoLabel(model.cacheContents)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// One request: its image, and where the last load found it.
private struct TileView: View {
    let item: CachingDemoModel.Item
    let tile: CachingDemoModel.Tile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color(.secondarySystemGroupedBackground)
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay {
                    if let image = tile.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .opacity(tile.isLoading ? 0.4 : 1)
                    } else if tile.isFailure {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
                .overlay {
                    if tile.isLoading {
                        ProgressView()
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    // Over the placeholder rather than a photo, so it reads.
                    if tile.isFailure && !tile.isLoading {
                        DemoBadge("Failed", color: .red)
                            .padding(4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(item.title)
                .font(.subheadline.weight(.semibold))
            DemoMonoLabel(item.subtitle)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 0) {
                DemoMonoLabel(tile.source?.title ?? " ", tint: tile.source?.color)
                DemoMonoLabel(tile.detail)
                    .lineLimit(2, reservesSpace: true)
                    .minimumScaleFactor(0.8)
            }
            .opacity(tile.isLoading ? 0.4 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Panel

/// The caches: which disk cache, the policy, what each layer holds, and the
/// calls that read and write them directly.
private struct CachingPanel: View {
    @ObservedObject var model: CachingDemoModel

    var body: some View {
        List {
            Section {
                Picker("Disk Cache", selection: $model.kind) {
                    ForEach(CachingDemoModel.Kind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Disk Cache")
            } footer: {
                Text(model.kind.summary)
            }

            policySection
            entriesSection(model.kind == .urlCache ? "In URLCache" : "On Disk", rows: model.diskRows, footer: model.diskFooter)
            entriesSection("In Memory", rows: model.memoryRows, footer: model.memoryFooter)
            DirectAccessSection(model: model)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
    }

    private var policySection: some View {
        let footer: LocalizedStringKey = model.kind == .urlCache
            ? "The policy decides what the pipeline writes to a `DataCache`. The `URLCache` pipeline has none."
            : "The policy is part of the configuration, so each pick builds a new pipeline, with its disk cache emptied, and loads the three requests into it. The switch starts over the same way. Beside each policy is what its last load left on the disk, in orange if the switch was on."
        return Section {
            Picker("Policy", selection: $model.policy) {
                ForEach(CachingDemoModel.Policy.allCases) { policy in
                    PolicyRow(policy: policy, result: model.results[policy])
                        .tag(policy)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Toggle(isOn: $model.isDiskWriteDisabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(".disableDiskCacheWrites")
                        .font(.system(.subheadline, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("On all three requests")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("dataCachePolicy")
                .textCase(nil)
        } footer: {
            Text(footer)
        }
        .disabled(model.kind == .urlCache)
    }

    private func entriesSection(_ title: String, rows: [CachingDemoModel.EntryRow], footer: String) -> some View {
        Section {
            ForEach(rows) { row in
                EntryView(row: row)
            }
        } header: {
            Text(title)
        } footer: {
            // Parsed as Markdown, which a `String` passed as is wouldn't be.
            Text(LocalizedStringKey(footer))
        }
    }
}

private struct PolicyRow: View {
    let policy: CachingDemoModel.Policy
    let result: CachingDemoModel.PolicyResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(policy.name)
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if let result {
                    DemoMonoLabel(result.text, tint: result.isOptionOn ? .orange : nil)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Text(policy.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A key, and what a cache holds under it.
private struct EntryView: View {
    let row: CachingDemoModel.EntryRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .font(.subheadline)
                    .foregroundStyle(row.isStored ? .primary : .secondary)
                Spacer(minLength: 8)
                DemoMonoLabel(row.status, tint: row.tint ?? (row.isStored ? .primary : nil))
                    .lineLimit(1)
                    .fixedSize()
            }
            DemoMonoLabel(row.detail)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

/// `pipeline.cache`, called with one of the three requests.
private struct DirectAccessSection: View {
    @ObservedObject var model: CachingDemoModel

    var body: some View {
        Section {
            Picker("Request", selection: $model.directItem) {
                ForEach(CachingDemoModel.Item.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            KeyRow(name: "makeImageCacheKey(for:)", value: "an opaque ImageCacheKey of the image ID, scale, thumbnail, and processors")
            KeyRow(name: "makeDataCacheKey(for:)", value: model.directKeys.dataKey)
            KeyRow(name: "DataCache.filename(for:)", value: model.directKeys.filename)

            ForEach(CachingDemoModel.Operation.allCases) { operation in
                if operation == .removeAll {
                    Menu {
                        Button("[.memory]") { model.perform(.removeAll, caches: [.memory]) }
                        Button("[.disk]") { model.perform(.removeAll, caches: [.disk]) }
                        Button("[.all]", role: .destructive) { model.perform(.removeAll, caches: [.all]) }
                    } label: {
                        OperationLabel(operation: operation, result: model.directResults[operation])
                    }
                } else {
                    Button {
                        model.perform(operation)
                    } label: {
                        OperationLabel(operation: operation, result: model.directResults[operation])
                    }
                }
            }

            DemoLink(.pipelineDelegate)
        } header: {
            Text("pipeline.cache")
                .textCase(nil)
        } footer: {
            Text("Tap a call to make it with the request above. The two stores write a picture that names the call, so a read shows where its image came from. A direct store doesn't go through the delegate's `willCache`, so the probe counts no disk write for it, and On Disk lists it as direct. A delegate can change both keys with `cacheKey(for:pipeline:)`, as Pipeline Delegate does.")
        }
    }
}

private struct KeyRow: View {
    let name: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            DemoMonoLabel(value)
                .textSelection(.enabled)
        }
    }
}

/// A call, and what it returned the last time.
private struct OperationLabel: View {
    let operation: CachingDemoModel.Operation
    let result: CachingDemoModel.DirectResult?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(operation.name)
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                DemoMonoLabel(result?.text ?? operation.hint, tint: result?.tint)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            if let image = result?.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

// MARK: - Model

@MainActor
private final class CachingDemoModel: ObservableObject {
    enum Kind: CaseIterable, Identifiable {
        case urlCache
        case dataCache

        var id: Self { self }

        var title: String {
            switch self {
            case .urlCache: "URLCache"
            case .dataCache: "DataCache"
            }
        }

        var summary: LocalizedStringKey {
            switch self {
            case .urlCache: "`.withURLCache`, the default: `URLSession`'s HTTP cache, which keeps each response as the server sent it and honors its cache-control headers."
            case .dataCache: "`.withDataCache`: the pipeline's own LRU disk cache, which ignores cache-control. The policy decides what goes in."
            }
        }
    }

    enum Policy: CaseIterable, Identifiable {
        case automatic
        case storeOriginalData
        case storeEncodedImages
        case storeAll

        var id: Self { self }

        var name: String {
            switch self {
            case .automatic: ".automatic"
            case .storeOriginalData: ".storeOriginalData"
            case .storeEncodedImages: ".storeEncodedImages"
            case .storeAll: ".storeAll"
            }
        }

        var value: ImagePipeline.DataCachePolicy {
            switch self {
            case .automatic: .automatic
            case .storeOriginalData: .storeOriginalData
            case .storeEncodedImages: .storeEncodedImages
            case .storeAll: .storeAll
            }
        }

        var summary: String {
            switch self {
            case .automatic: "The downloaded data of an unprocessed request, the encoded image of a processed one"
            case .storeOriginalData: "The default. Only the downloaded data: a resize or a thumbnail is made again from it"
            case .storeEncodedImages: "Only encoded images, the unprocessed one's included"
            case .storeAll: "The downloaded data, and the encoded image of a processed request"
            }
        }

        /// The directory of the policy's disk cache, under the prefix that
        /// `-demoDeterministic 1` empties.
        var cacheName: String {
            "com.github.kean.NukeDemo.Caching.\(self)"
        }
    }

    /// One of the three requests the screen loads.
    enum Item: CaseIterable, Identifiable {
        case original
        case resize
        case thumbnail

        var id: Self { self }

        var title: String {
            switch self {
            case .original: "Original"
            case .resize: "Resize"
            case .thumbnail: "Thumbnail"
            }
        }

        var subtitle: String {
            switch self {
            case .original: "JPEG · as is"
            case .resize: "WebP · 160 pt"
            case .thumbnail: "PNG · 160 pt"
            }
        }

        var format: String {
            switch self {
            case .original: "JPEG"
            case .resize: "WebP"
            case .thumbnail: "PNG"
            }
        }

        /// A different image for each, read when a load starts, so that it
        /// follows the demo's offline switch.
        var url: URL {
            switch self {
            case .original: DemoImages.landscape
            case .resize: DemoImages.webp
            case .thumbnail: DemoImages.png
            }
        }
    }

    /// A key the requests read or write under: a request's own, or, for the
    /// two that process, the key of the image they start from – the URL
    /// alone, which is where the pipeline keeps the downloaded data.
    struct Slot: Hashable {
        let item: Item
        let isSource: Bool

        static let all: [Slot] = [
            Slot(item: .original, isSource: false),
            Slot(item: .resize, isSource: true),
            Slot(item: .resize, isSource: false),
            Slot(item: .thumbnail, isSource: true),
            Slot(item: .thumbnail, isSource: false)
        ]

        /// The slot of the key that is the URL alone.
        static func source(of item: Item) -> Slot {
            Slot(item: item, isSource: item != .original)
        }

        var title: String {
            isSource ? "\(item.title) · source" : item.title
        }
    }

    /// A write to the disk cache that the screen knows of.
    struct Write {
        enum Kind {
            /// The downloaded data: `willCache` with no image.
            case data
            /// An image the pipeline encoded: `willCache` with one.
            case encoded
            /// A store through `pipeline.cache` on this screen.
            case direct

            var name: String {
                switch self {
                case .data: "data"
                case .encoded: "encoded"
                case .direct: "direct"
                }
            }
        }

        let kind: Kind
        /// Written though the request had `.disableDiskCacheWrites`.
        let ignoredOption: Bool
    }

    struct Tile {
        var image: UIImage?
        var isLoading = false
        var isFailure = false
        var source: Source?
        var detail = " "
    }

    /// Where the image of a tile came from.
    struct Source {
        let title: String
        let color: Color

        static let memory = Source(title: "memory", color: .green)
        static let disk = Source(title: "disk", color: .blue)
        static let network = Source(title: "network", color: .orange)
        static let fixture = Source(title: "fixture", color: .orange)
        static let urlCache = Source(title: "URLCache", color: .teal)
        static let failed = Source(title: "failed", color: .red)
    }

    struct EntryRow: Identifiable {
        let id: String
        let title: String
        /// The key, or what the entry is.
        let detail: String
        let status: String
        var tint: Color?
        let isStored: Bool
    }

    struct PolicyResult {
        let fileCount: Int
        let byteCount: Int
        let isOptionOn: Bool

        var text: String {
            "\(demoCount(fileCount, "file")) · \(demoByteCount(byteCount))"
        }
    }

    enum Operation: CaseIterable, Identifiable {
        case memoryRead
        case cachedImage
        case cachedData
        case containsCachedImage
        case containsData
        case storeCachedImage
        case storeCachedData
        case removeCachedImage
        case removeAll

        var id: Self { self }

        var name: String {
            switch self {
            case .memoryRead: "cache[request]"
            case .cachedImage: "cachedImage(for:)"
            case .cachedData: "cachedData(for:)"
            case .containsCachedImage: "containsCachedImage(for:caches:)"
            case .containsData: "containsData(for:)"
            case .storeCachedImage: "storeCachedImage(_:for:)"
            case .storeCachedData: "storeCachedData(_:for:)"
            case .removeCachedImage: "removeCachedImage(for:)"
            case .removeAll: "removeAll(caches:)"
            }
        }

        /// What the call does, until it is made.
        var hint: String {
            switch self {
            case .memoryRead: "reads the memory cache"
            case .cachedImage: "reads memory, then the disk, and decodes"
            case .cachedData: "reads the disk"
            case .containsCachedImage: "checks each layer"
            case .containsData: "checks the disk"
            case .storeCachedImage: "writes a picture to memory and, encoded, to disk"
            case .storeCachedData: "writes a picture's JPEG to disk"
            case .removeCachedImage: "removes the entries of this request"
            case .removeAll: "empties a layer, for every request"
            }
        }
    }

    struct DirectResult: Sendable {
        var text: String
        var image: UIImage?
        var tint: Color?
    }

    struct DirectKeys {
        var dataKey = " "
        var filename = " "
    }

    /// Both processed requests fit the image in this, in points.
    static let targetSize = CGSize(width: 160, height: 160)

    @Published var kind: Kind = .dataCache {
        didSet {
            guard kind != oldValue else { return }
            directResults.removeAll()
            load()
        }
    }
    @Published var policy: Policy = .storeOriginalData {
        didSet {
            guard policy != oldValue else { return }
            rebuild()
        }
    }
    @Published var isDiskWriteDisabled = false {
        didSet {
            guard isDiskWriteDisabled != oldValue else { return }
            rebuild()
        }
    }
    @Published var directItem: Item = .original {
        didSet {
            directResults.removeAll()
            refreshDirectKeys()
        }
    }

    @Published private(set) var tiles: [Item: Tile] = [:]
    @Published private(set) var cacheContents = " "
    /// The probe's figures for the pipeline on screen, in two lines.
    @Published private(set) var counts = [" ", " "]
    @Published private(set) var mismatch: (text: String, isProblem: Bool)?
    /// What the last load of each policy left on the disk.
    @Published private(set) var results: [Policy: PolicyResult] = [:]
    @Published private(set) var diskRows: [EntryRow] = []
    @Published private(set) var diskFooter = ""
    @Published private(set) var memoryRows: [EntryRow] = []
    @Published private(set) var memoryFooter = ""
    @Published private(set) var directKeys = DirectKeys()
    @Published private(set) var directResults: [Operation: DirectResult] = [:]

    private let urlCachePipeline: ImagePipeline
    private let urlCacheImageCache: ImageCache
    private var dataCachePipeline: ImagePipeline
    private var dataCacheImageCache: ImageCache
    private var dataCache: DataCache?
    /// Counts the `DataCache` pipelines, so that what an earlier one reports
    /// late is left out.
    private var generation = 0
    /// What the disk cache of the current `DataCache` pipeline was given, by
    /// key.
    private var writes: [String: Write] = [:]
    private var loads: [Task<Void, Never>] = []
    private var refresher: Task<Void, Never>?
    private var isStarted = false
    private let relay: Relay

    private var pipeline: ImagePipeline {
        switch kind {
        case .urlCache: urlCachePipeline
        case .dataCache: dataCachePipeline
        }
    }

    private var imageCache: ImageCache {
        switch kind {
        case .urlCache: urlCacheImageCache
        case .dataCache: dataCacheImageCache
        }
    }

    private var urlCache: URLCache? {
        (urlCachePipeline.configuration.dataLoader as? DataLoader)?.session.configuration.urlCache
    }

    init() {
        // Each pipeline has a memory cache of its own, so that switching
        // between them shows what the disk cache alone is doing. They record
        // diagnostics: each tile reads which key the disk answered from its
        // task's record.
        var configuration = ImagePipeline.Configuration.withURLCache
        urlCacheImageCache = ImageCache()
        configuration.imageCache = urlCacheImageCache
        configuration.isDiagnosticsEnabled = true
        urlCachePipeline = DemoPipelineProbe.makePipeline("Caching · URLCache", configuration: configuration)

        let relay = Relay()
        let setup = Self.makeDataCachePipeline(policy: .storeOriginalData, isDiskWriteDisabled: false, generation: 0, relay: relay)
        dataCachePipeline = setup.pipeline
        dataCacheImageCache = setup.imageCache
        dataCache = setup.dataCache
        self.relay = relay
        relay.model = self
    }

    // MARK: Pipelines

    private struct Setup {
        let pipeline: ImagePipeline
        let imageCache: ImageCache
        let dataCache: DataCache?
    }

    /// A pipeline with a `DataCache` that keeps what `policy` says.
    ///
    /// The probe reports each `willCache` call on the pipeline's actor, just
    /// before the pipeline stores the data, which is how the list knows what
    /// each file is.
    private static func makeDataCachePipeline(policy: Policy, isDiskWriteDisabled: Bool, generation: Int, relay: Relay) -> Setup {
        var configuration = ImagePipeline.Configuration.withDataCache(name: policy.cacheName)
        configuration.dataCachePolicy = policy.value
        let imageCache = ImageCache()
        configuration.imageCache = imageCache
        configuration.isDiagnosticsEnabled = true
        let dataCache = configuration.dataCache as? DataCache
        let label = "Caching · \(policy.name)\(isDiskWriteDisabled ? " · no disk writes" : "")"
        let pipeline = DemoPipelineProbe.makePipeline(label, configuration: configuration, onEvent: { event in
            guard case .willCache(_, let isEncodedImage, let storedByteCount) = event.kind, storedByteCount != nil else { return }
            let request = event.request
            Task { @MainActor in
                relay.model?.didCache(request, isEncodedImage: isEncodedImage, generation: generation)
            }
        })
        return Setup(pipeline: pipeline, imageCache: imageCache, dataCache: dataCache)
    }

    /// A new pipeline for the policy and the switch, with an empty disk
    /// cache, so that the counts, too, are of this run alone.
    private func rebuild() {
        cancelLoads()
        generation += 1
        let replaced = dataCache
        let setup = Self.makeDataCachePipeline(policy: policy, isDiskWriteDisabled: isDiskWriteDisabled, generation: generation, relay: relay)
        dataCachePipeline = setup.pipeline
        dataCacheImageCache = setup.imageCache
        dataCache = setup.dataCache
        writes.removeAll()
        directResults.removeAll()
        loadWhenEmptied(after: replaced)
    }

    /// Loads once the disk cache is empty.
    ///
    /// `DataCache` stages a change and makes it a moment later, and the cache
    /// of the pipeline this one replaced can still hold a write for the same
    /// directory: it goes first, then the removal.
    private func loadWhenEmptied(after replaced: DataCache? = nil) {
        let generation = self.generation
        let dataCache = self.dataCache
        Task { [weak self] in
            await replaced?.flush()
            dataCache?.removeAll()
            await dataCache?.flush()
            guard let self, generation == self.generation else { return }
            self.load()
        }
    }

    private func didCache(_ request: ImageRequest, isEncodedImage: Bool, generation: Int) {
        guard generation == self.generation else { return }
        let key = dataCachePipeline.cache.makeDataCacheKey(for: request)
        writes[key] = Write(kind: isEncodedImage ? .encoded : .data, ignoredOption: request.options.contains(.disableDiskCacheWrites))
        refresh()
    }

    // MARK: Loading

    func startIfNeeded() {
        guard !isStarted else { return }
        isStarted = true
        loadWhenEmptied()
    }

    /// Starts the three requests at once.
    func load() {
        cancelLoads()
        refreshDirectKeys()
        let pipeline = self.pipeline
        for item in Item.allCases {
            tiles[item, default: Tile()].isLoading = true
            let task = pipeline.imageTask(with: makeRequest(item))
            loads.append(Task { [weak self] in
                let result: Result<ImageResponse, ImagePipeline.Error>
                do throws(ImagePipeline.Error) {
                    result = .success(try await task.response)
                } catch {
                    result = .failure(error)
                }
                guard let self, !Task.isCancelled else { return }
                self.didFinish(item, task: task, result: result)
            })
        }
        refresh()
    }

    func cancel() {
        cancelLoads()
    }

    private func cancelLoads() {
        // Cancelling the task that waits for a response cancels the image
        // task too.
        for load in loads {
            load.cancel()
        }
        loads.removeAll()
        for item in Item.allCases {
            tiles[item]?.isLoading = false
        }
    }

    func clear(_ caches: ImagePipeline.Cache.Caches) {
        pipeline.cache.removeAll(caches: caches)
        if caches.contains(.disk) {
            writes.removeAll()
            if kind == .urlCache {
                // `ImagePipeline.Cache` doesn't manage `URLCache`: it belongs
                // to the URL loading system.
                urlCache?.removeAllCachedResponses()
            }
        }
        refresh()
    }

    private func makeRequest(_ item: Item) -> ImageRequest {
        // The option changes nothing `URLCache` does, and its switch is off
        // there.
        let options: ImageRequest.Options = kind == .dataCache && isDiskWriteDisabled ? [.disableDiskCacheWrites] : []
        var request = ImageRequest(url: item.url, options: options)
        switch item {
        case .original:
            break
        case .resize:
            request.processors = [.resize(size: Self.targetSize, contentMode: .aspectFit)]
        case .thumbnail:
            request.thumbnail = ImageRequest.ThumbnailOptions(size: Self.targetSize, contentMode: .aspectFit)
        }
        return request
    }

    private func makeRequest(for slot: Slot) -> ImageRequest {
        slot.isSource ? ImageRequest(url: slot.item.url) : makeRequest(slot.item)
    }

    private func didFinish(_ item: Item, task: ImageTask, result: Result<ImageResponse, ImagePipeline.Error>) {
        switch result {
        case .success(let response):
            let (source, detail) = describe(response, item: item, metrics: task.metrics)
            tiles[item] = Tile(image: response.image, source: source, detail: detail)
        case .failure(.cancelled):
            tiles[item]?.isLoading = false
        case .failure(let error):
            // The case, and under it the code of the error it wraps.
            let detail = task.metrics?.error.map { error in
                [error.code, error.underlyingCode.map { "error \($0)" }].compactMap { $0 }.joined(separator: "\n")
            }
            tiles[item] = Tile(isFailure: true, source: .failed, detail: detail ?? error.description)
        }
        refresh()
    }

    /// Where the image came from, and, for the disk, whether it was the
    /// request's own entry or the downloaded data, made into the image again.
    private func describe(_ response: ImageResponse, item: Item, metrics: ImageTask.Metrics?) -> (Source, String) {
        switch response.cacheType {
        case .memory?:
            return (.memory, Self.pixelSize(of: response.image))
        case nil:
            let bytes = metrics?.bytes.map { demoByteCount($0.downloaded) } ?? "–"
            if let metrics, metrics.isServedFromHTTPCache {
                // A stale response goes back to the server, which answers
                // 304 if it hasn't changed.
                return (.urlCache, metrics.isRevalidated ? "\(bytes), revalidated" : bytes)
            }
            if DemoFixture.isFixture(response.request.url) {
                return (.fixture, bytes)
            }
            if kind == .urlCache, metrics?.urlSessionMetrics == nil, DemoNetworkConditions.current != nil {
                // Behind the conditions, the record has no session metrics
                // to tell a `URLCache` answer by.
                return (.network, "\(bytes), or URLCache")
            }
            return (.network, "\(bytes) down")
        case .disk?:
            // The first disk lookup of the request's own job is for its own
            // key; a later one is for the downloaded data.
            let root = metrics?.jobs.first { $0.id == metrics?.rootJobID }
            let own = root?.stages.first { $0.kind == .diskLookup }
            if own?.result == .hit {
                let key = pipeline.cache.makeDataCacheKey(for: makeRequest(item))
                let kind = writes[key]?.kind.name ?? "stored"
                return (.disk, "\(kind) · \(own?.bytes.map(demoByteCount) ?? "–")")
            }
            let hit = metrics?.jobs.flatMap(\.stages).first { $0.kind == .diskLookup && $0.result == .hit }
            let made = item == .thumbnail ? "thumbnail" : "resized"
            return (.disk, "\(made) from \(hit?.bytes.map(demoByteCount) ?? "–")")
        }
    }

    // MARK: Reading the Caches

    /// Reads what the caches hold, a moment after the last change, so that a
    /// burst of writes is read once, after `DataCache` has made them.
    private func refresh() {
        refresher?.cancel()
        refreshMemory()
        refreshCounts()
        let kind = self.kind
        let policy = self.policy
        let isOptionOn = isDiskWriteDisabled
        let pipeline = self.pipeline
        let dataCache = kind == .dataCache ? self.dataCache : nil
        let urlCache = kind == .urlCache ? self.urlCache : nil
        let keys = Dictionary(uniqueKeysWithValues: Slot.all.map { slot in
            (slot, pipeline.cache.makeDataCacheKey(for: makeRequest(for: slot)))
        })
        let urls = Dictionary(uniqueKeysWithValues: Item.allCases.map { ($0, $0.url) })
        refresher = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            await dataCache?.flush()
            let caches = await DemoPipelineProbe.sampleCaches(for: pipeline)
            let listing = await Task.detached(priority: .userInitiated) {
                if let dataCache {
                    Self.readDisk(dataCache, keys: keys)
                } else if let urlCache {
                    Self.readURLCache(urlCache, urls: urls)
                } else {
                    Listing()
                }
            }.value
            guard let self, !Task.isCancelled, kind == self.kind else { return }
            self.apply(listing, keys: keys, urls: urls, caches: caches)
            if kind == .dataCache, policy == self.policy {
                self.results[policy] = PolicyResult(fileCount: listing.files.count, byteCount: listing.files.values.reduce(0, +), isOptionOn: isOptionOn)
            }
            self.refreshCounts()
        }
    }

    /// What is on the disk.
    private struct Listing: Sendable {
        struct Entry: Sendable {
            let byteCount: Int
            let format: String
            /// The status of a redirect `URLCache` keeps for the URL, which
            /// the entry is the target of.
            var redirect: Int?
        }

        /// By slot; for `URLCache`, by the slot of the request's URL.
        var entries: [Slot: Entry] = [:]
        /// The size of every file in the cache, by name.
        var files: [String: Int] = [:]
        /// The files that no key of the requests names.
        var unknown: [String] = []
    }

    /// Lists the directory of the cache, and checks each key with
    /// `containsData(for:)`. A key's file is the one `filename(for:)` names.
    private nonisolated static func readDisk(_ dataCache: DataCache, keys: [Slot: String]) -> Listing {
        var listing = Listing()
        let contents = (try? FileManager.default.contentsOfDirectory(at: dataCache.path, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)) ?? []
        for url in contents {
            listing.files[url.lastPathComponent] = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        var named = Set<String>()
        for (slot, key) in keys {
            guard let filename = dataCache.filename(for: key), let url = dataCache.url(for: key) else { continue }
            named.insert(filename)
            guard dataCache.containsData(for: key) else { continue }
            let handle = try? FileHandle(forReadingFrom: url)
            let prefix = try? handle?.read(upToCount: 32)
            try? handle?.close()
            listing.entries[slot] = Listing.Entry(byteCount: listing.files[filename] ?? 0, format: formatName(of: prefix))
        }
        listing.unknown = listing.files.keys.filter { !named.contains($0) }.sorted()
        return listing
    }

    /// The response `URLCache` keeps for each URL. For a redirect, which it
    /// keeps under the URL that was requested, the response of the target.
    private nonisolated static func readURLCache(_ urlCache: URLCache, urls: [Item: URL]) -> Listing {
        var listing = Listing()
        for (item, url) in urls {
            guard var cached = urlCache.cachedResponse(for: URLRequest(url: url)) else { continue }
            var redirect: Int?
            if let response = cached.response as? HTTPURLResponse, (300..<400).contains(response.statusCode),
               let location = response.value(forHTTPHeaderField: "Location"),
               let target = URL(string: location, relativeTo: url) {
                redirect = response.statusCode
                guard let targetResponse = urlCache.cachedResponse(for: URLRequest(url: target.absoluteURL)) else {
                    listing.entries[Slot.source(of: item)] = Listing.Entry(byteCount: 0, format: "–", redirect: redirect)
                    continue
                }
                cached = targetResponse
            }
            listing.entries[Slot.source(of: item)] = Listing.Entry(byteCount: cached.data.count, format: formatName(of: cached.data.prefix(32)), redirect: redirect)
            listing.files[url.absoluteString] = cached.data.count
        }
        return listing
    }

    private func apply(_ listing: Listing, keys: [Slot: String], urls: [Item: URL], caches: DemoPipelineDiagnostics.Caches) {
        switch kind {
        case .dataCache:
            var rows = Slot.all.map { slot in
                let key = keys[slot] ?? ""
                guard let entry = listing.entries[slot] else {
                    return EntryRow(id: key, title: slot.title, detail: key, status: "–", isStored: false)
                }
                let write = writes[key]
                return EntryRow(
                    id: key,
                    title: slot.title,
                    detail: key,
                    status: "\(write?.kind.name ?? "unaccounted for") · \(entry.format) · \(demoByteCount(entry.byteCount))",
                    tint: write?.ignoredOption == true ? .orange : nil,
                    isStored: true
                )
            }
            rows += listing.unknown.map { filename in
                EntryRow(id: filename, title: "No key of these requests", detail: filename, status: demoByteCount(listing.files[filename] ?? 0), isStored: true)
            }
            diskRows = rows
            diskFooter = "The key of each request, and of the image a processed one starts from, with what the disk keeps under it: **data** is the file as downloaded, **encoded** an image the pipeline encoded, **direct** a store through `pipeline.cache` below. Orange is a write that the request's `.disableDiskCacheWrites` didn't stop. `DataCache` holds \(demoCount(caches.dataCacheCount ?? 0, "file")), \(demoByteCount(caches.dataCacheSize ?? 0))."
        case .urlCache:
            diskRows = Item.allCases.map { item in
                let url = urls[item]?.absoluteString ?? ""
                let title = "\(item.title) · \(item.format) response"
                guard let entry = listing.entries[Slot.source(of: item)] else {
                    return EntryRow(id: url, title: title, detail: url, status: "–", isStored: false)
                }
                var status = "\(entry.format) · \(demoByteCount(entry.byteCount))"
                if let redirect = entry.redirect {
                    status = entry.byteCount > 0 ? "\(redirect) → \(status)" : "\(redirect), no target"
                }
                return EntryRow(id: url, title: title, detail: url, status: status, isStored: true)
            }
            var footer = "One response per URL, as the server sent it. The resize and the thumbnail aren't kept: they are made again from the response after a memory miss. A revalidated response went back to the server, which said it hadn't changed."
            if listing.entries.values.contains(where: { $0.redirect != nil }) {
                footer += " A redirect is kept as a response of its own, under the URL that was requested; the size is of the response it leads to."
            }
            if DemoFixtureMode.isOffline {
                footer += " Offline, the fixtures don't go through `URLSession`, so nothing is kept here."
            }
            if DemoNetworkConditions.current != nil {
                footer += " While the network conditions are on, a task's record doesn't say whether `URLCache` answered, so the tiles can't tell; the count under them can."
            }
            if let usage = caches.urlCacheDiskUsage {
                footer += " `URLCache` uses \(demoByteCount(usage)) on disk, for every pipeline that shares it."
            }
            diskFooter = footer
        }
    }

    private func refreshMemory() {
        let pipeline = self.pipeline
        let imageCache = self.imageCache
        memoryRows = Item.allCases.map { item in
            // The cache itself rather than `pipeline.cache`: a read here isn't
            // the pipeline's, and the probe doesn't count it.
            let container = imageCache[pipeline.cache.makeImageCacheKey(for: makeRequest(item))]
            let id = "\(item)"
            guard let cgImage = container?.image.cgImage else {
                return EntryRow(id: id, title: item.title, detail: "no entry", status: "–", isStored: false)
            }
            return EntryRow(
                id: id,
                title: item.title,
                detail: "decoded, \(cgImage.width)×\(cgImage.height) px",
                status: demoByteCount(cgImage.bytesPerRow * cgImage.height),
                isStored: true
            )
        }
        memoryFooter = "The decoded image each request ended with, under a key of its image ID, scale, thumbnail, and processors. `ImageCache` holds \(demoCount(imageCache.totalCount, "image")), \(demoByteCount(imageCache.totalCost))."
    }

    /// The probe's figures for the pipeline on screen, since it was built.
    private func refreshCounts() {
        guard let figures = DemoPipelineProbe.diagnostics(for: pipeline) else { return }
        let loads = figures.fixtureLoadCount > 0
            ? demoCount(figures.fixtureLoadCount, "fixture load")
            : demoCount(figures.downloadCount, "download")
        let stored = diskRows.filter(\.isStored).count
        switch kind {
        case .dataCache:
            cacheContents = "\(imageCache.totalCount) in memory · \(stored) on disk"
            let encoding = figures.encoding.count > 0 ? String(format: " · %.1f ms avg", figures.encoding.average * 1000) : ""
            counts = [
                "\(loads) · \(figures.diskCacheHitCount) of \(demoCount(figures.diskCacheLookupCount, "disk lookup")) hit",
                "\(demoCount(figures.diskWriteCount, "disk write")), \(figures.encodedImageWriteCount) encoded · \(demoCount(figures.encoding.count, "encode"))\(encoding)"
            ]
        case .urlCache:
            cacheContents = "\(imageCache.totalCount) in memory · \(stored) in URLCache"
            counts = [
                "\(loads) · \(figures.httpCacheLoadCount) from URLCache alone",
                "no DataCache: the pipeline writes nothing to disk"
            ]
        }
        if kind == .dataCache, isDiskWriteDisabled {
            let ignored = writes.values.filter(\.ignoredOption).count
            mismatch = ignored > 0
                ? (".disableDiskCacheWrites on: \(demoCount(ignored, "image")) written anyway", true)
                : (".disableDiskCacheWrites on: nothing written", false)
        } else {
            mismatch = nil
        }
    }

    // MARK: Direct Access

    private func refreshDirectKeys() {
        let key = pipeline.cache.makeDataCacheKey(for: makeRequest(directItem))
        directKeys.dataKey = key
        directKeys.filename = kind == .dataCache ? (dataCache?.filename(for: key) ?? "–") : "no DataCache in this pipeline"
    }

    /// Makes the call off the main thread, as a read from the disk should be.
    func perform(_ operation: Operation, caches: ImagePipeline.Cache.Caches = [.all]) {
        let item = directItem
        let kind = self.kind
        let generation = self.generation
        let request = makeRequest(item)
        let pipeline = self.pipeline
        let dataCache = kind == .dataCache ? self.dataCache : nil
        let picture: UIImage? = switch operation {
        case .storeCachedImage: Self.makePicture(title: "storeCachedImage", color: .systemIndigo)
        case .storeCachedData: Self.makePicture(title: "storeCachedData", color: .systemTeal)
        default: nil
        }
        refreshDirectKeys()
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                Self.call(operation, request: request, pipeline: pipeline, dataCache: dataCache, caches: caches, picture: picture)
            }.value
            guard let self, kind == self.kind, generation == self.generation else { return }
            let key = pipeline.cache.makeDataCacheKey(for: request)
            if outcome.didWrite {
                self.writes[key] = Write(kind: .direct, ignoredOption: false)
            }
            if caches.contains(.disk) {
                switch operation {
                case .removeCachedImage: self.writes[key] = nil
                case .removeAll: self.writes.removeAll()
                default: break
                }
            }
            if item == self.directItem {
                self.directResults[operation] = outcome.result
            }
            self.refresh()
        }
    }

    private struct Outcome: Sendable {
        var result: DirectResult
        var didWrite = false
    }

    private nonisolated static func call(_ operation: Operation, request: ImageRequest, pipeline: ImagePipeline, dataCache: DataCache?, caches: ImagePipeline.Cache.Caches, picture: UIImage?) -> Outcome {
        let cache = pipeline.cache
        switch operation {
        case .memoryRead:
            guard let container = cache[request] else {
                return Outcome(result: DirectResult(text: "nil"))
            }
            return Outcome(result: DirectResult(text: pixelSize(of: container.image), image: container.image))
        case .cachedImage:
            let isInMemory = cache.containsCachedImage(for: request, caches: [.memory])
            let start = ContinuousClock.now
            guard let container = cache.cachedImage(for: request) else {
                return Outcome(result: DirectResult(text: "nil"))
            }
            let elapsed = milliseconds(ContinuousClock.now - start)
            let from = isInMemory ? "from memory" : "decoded from disk"
            return Outcome(result: DirectResult(text: "\(pixelSize(of: container.image)), \(from) in \(elapsed)", image: container.image))
        case .cachedData:
            guard let data = cache.cachedData(for: request) else {
                return Outcome(result: DirectResult(text: dataCache == nil ? "nil: no DataCache" : "nil"))
            }
            return Outcome(result: DirectResult(text: "\(demoByteCount(data.count)) · \(formatName(of: data.prefix(32)))"))
        case .containsCachedImage:
            let memory = cache.containsCachedImage(for: request, caches: [.memory])
            let disk = cache.containsCachedImage(for: request, caches: [.disk])
            return Outcome(result: DirectResult(text: "[.memory] \(memory) · [.disk] \(disk)"))
        case .containsData:
            let contains = cache.containsData(for: request)
            return Outcome(result: DirectResult(text: dataCache == nil ? "\(contains): no DataCache" : "\(contains)"))
        case .storeCachedImage:
            guard let picture else { return Outcome(result: DirectResult(text: "–")) }
            cache.storeCachedImage(ImageContainer(image: picture), for: request)
            let memory = cache.containsCachedImage(for: request, caches: [.memory]) ? "memory: stored" : "memory: not stored"
            let disk = diskWriteResult(request: request, pipeline: pipeline, dataCache: dataCache)
            return Outcome(result: DirectResult(text: "\(memory) · \(disk.text)", image: picture, tint: disk.tint), didWrite: disk.didWrite)
        case .storeCachedData:
            guard let picture, let data = ImageEncoders.Default().encode(picture) else {
                return Outcome(result: DirectResult(text: "–"))
            }
            cache.storeCachedData(data, for: request)
            let disk = diskWriteResult(request: request, pipeline: pipeline, dataCache: dataCache)
            return Outcome(result: DirectResult(text: disk.text, image: picture, tint: disk.tint), didWrite: disk.didWrite)
        case .removeCachedImage:
            cache.removeCachedImage(for: request)
            let memory = cache.containsCachedImage(for: request, caches: [.memory])
            let disk = cache.containsData(for: request)
            return Outcome(result: DirectResult(text: "in memory: \(memory) · on disk: \(disk)"))
        case .removeAll:
            cache.removeAll(caches: caches)
            let name = caches == .all ? "[.all]" : caches == .memory ? "[.memory]" : "[.disk]"
            let note = caches.contains(.disk) && dataCache == nil ? "; no DataCache to empty" : ""
            return Outcome(result: DirectResult(text: "emptied \(name) for every request\(note)"))
        }
    }

    /// Whether a direct store reached the disk cache. The store stages the
    /// data, so a read of the key right after it returns the data.
    private nonisolated static func diskWriteResult(request: ImageRequest, pipeline: ImagePipeline, dataCache: DataCache?) -> (text: String, tint: Color?, didWrite: Bool) {
        guard let dataCache else {
            return ("disk: no DataCache", nil, false)
        }
        guard !request.options.contains(.disableDiskCacheWrites) else {
            return ("disk: skipped for .disableDiskCacheWrites", .green, false)
        }
        guard let data = dataCache.cachedData(for: pipeline.cache.makeDataCacheKey(for: request)) else {
            return ("disk: not stored", nil, false)
        }
        return ("disk: \(demoByteCount(data.count)) \(formatName(of: data.prefix(32)))", nil, true)
    }

    /// A picture that names the call that stored it, so that a read shows it.
    private static func makePicture(title: String, color: UIColor) -> UIImage {
        let size = CGSize(width: 480, height: 360)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let text = NSAttributedString(string: title, attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 34, weight: .bold),
                .foregroundColor: UIColor.white
            ])
            let bounds = text.size()
            text.draw(at: CGPoint(x: (size.width - bounds.width) / 2, y: (size.height - bounds.height) / 2))
        }
    }

    private nonisolated static func pixelSize(of image: UIImage) -> String {
        guard let cgImage = image.cgImage else { return "an image" }
        return "\(cgImage.width)×\(cgImage.height) px"
    }

    /// Takes the probe's reports to the model: the handler that receives them
    /// is made before the model exists.
    @MainActor
    private final class Relay {
        weak var model: CachingDemoModel?
    }
}

// MARK: - Helpers

/// The format of a file, from its first bytes, as its usual extension, such
/// as `"jpeg"`.
private func formatName(of prefix: Data?) -> String {
    guard let prefix, let type = AssetType(prefix) else { return "unknown" }
    return type.utType?.preferredFilenameExtension ?? type.rawValue
}

private func milliseconds(_ duration: Duration) -> String {
    let milliseconds = duration.demoTimeInterval * 1000
    return milliseconds < 10 ? String(format: "%.2f ms", milliseconds) : String(format: "%.0f ms", milliseconds)
}
