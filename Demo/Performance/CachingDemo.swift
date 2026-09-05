// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI

/// Demonstrates the cache layers: the memory cache, the HTTP disk cache
/// (`URLCache`), and the aggressive disk cache (``DataCache``).
///
/// ```swift
/// ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
/// ```
struct CachingDemo: View {
    @StateObject private var model = CachingDemoModel()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        List {
            Section {
                Picker("Disk Cache", selection: $model.kind) {
                    ForEach(CachingDemoModel.Kind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } footer: {
                Text(model.kind.summary)
            }

            Section {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(model.photos, id: \.self) { url in
                        SquareCell {
                            LazyImage(url: url) { state in
                                if let image = state.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Color(.secondarySystemBackground)
                                }
                            }
                            .pipeline(model.pipeline)
                            .onCompletion { model.didComplete(url, $0) }
                        }
                        .overlay(alignment: .bottomLeading) {
                            if let source = model.sources[url] {
                                DemoBadge(source.title, color: source.color)
                                    .padding(4)
                            }
                        }
                    }
                }
                .id(model.reloadToken)
                .listRowInsets(EdgeInsets())
            }

            Section("Cache Size") {
                LabeledContent("Memory", value: model.memorySize)
                LabeledContent(model.kind.diskTitle, value: model.diskSize)
            }

            Section {
                Button("Reload") { model.reload() }
                Button("Clear Memory Cache") { model.clear(caches: [.memory]) }
                Button("Clear Disk Cache") { model.clear(caches: [.disk]) }
                Button("Clear All Caches", role: .destructive) { model.clear(caches: [.all]) }
            }
        }
        .onAppear { model.refreshStats() }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Caching",
        "Nuke has two layers: a memory cache of decoded images and a disk cache of downloaded data. Every image on this screen shows where it came from. Clear the memory cache and reload to watch the disk serve them; clear both to go back to the network.",
        code: """
        ImagePipeline.shared = ImagePipeline(
            configuration: .withDataCache
        )
        """,
        points: [
            .init("Memory cache", "`ImageCache` holds decoded, processed images. It is an LRU cache with a cost limit and it empties itself on a memory warning."),
            .init("URLCache", "The default disk cache. It speaks HTTP, so it revalidates with the server and honors cache-control."),
            .init("DataCache", "An aggressive LRU cache on disk that ignores cache-control. Faster, and the right choice for images that never change."),
            .init("Both, not either", "The disk cache stores the original data, the memory cache the decoded bitmap. A hit on disk still costs a decode.")
        ]
    )
}

@MainActor
private final class CachingDemoModel: ObservableObject {
    enum Kind: String, CaseIterable, Identifiable {
        case urlCache
        case dataCache

        var id: Self { self }

        var title: String {
            switch self {
            case .urlCache: "URLCache"
            case .dataCache: "DataCache"
            }
        }

        var summary: String {
            switch self {
            case .urlCache: "The default configuration. An HTTP disk cache that respects cache-control headers."
            case .dataCache: "An aggressive LRU disk cache that ignores cache-control. Faster, but the images never get validated."
            }
        }

        var diskTitle: String {
            switch self {
            case .urlCache: "Disk (URLCache)"
            case .dataCache: "Disk (DataCache)"
            }
        }
    }

    struct Source {
        let title: String
        let color: Color
    }

    let photos = Array(DemoImages.photos.prefix(9))

    @Published var kind: Kind = .urlCache {
        didSet { reload() }
    }

    @Published private(set) var reloadToken = UUID()
    @Published private(set) var sources: [URL: Source] = [:]
    @Published private(set) var memorySize = "–"
    @Published private(set) var diskSize = "–"

    private let urlCachePipeline: ImagePipeline
    private let dataCachePipeline: ImagePipeline
    private let dataCache: DataCache?

    var pipeline: ImagePipeline {
        switch kind {
        case .urlCache: urlCachePipeline
        case .dataCache: dataCachePipeline
        }
    }

    init() {
        // Both pipelines get their own memory cache so that switching between
        // them shows what the disk cache alone is doing.
        var urlCacheConfiguration = ImagePipeline.Configuration.withURLCache
        urlCacheConfiguration.imageCache = ImageCache()
        urlCachePipeline = ImagePipeline(configuration: urlCacheConfiguration)

        var dataCacheConfiguration = ImagePipeline.Configuration.withDataCache(name: "com.github.kean.NukeDemo.DataCache")
        dataCacheConfiguration.imageCache = ImageCache()
        dataCache = dataCacheConfiguration.dataCache as? DataCache
        dataCachePipeline = ImagePipeline(configuration: dataCacheConfiguration)
    }

    func didComplete(_ url: URL, _ result: Result<ImageResponse, ImagePipeline.Error>) {
        guard case .success(let response) = result else { return }
        sources[url] = switch response.cacheType {
        case .memory?: Source(title: "Memory", color: .green)
        case .disk?: Source(title: "Disk", color: .blue)
        case nil: Source(title: "Network", color: .orange)
        }
        refreshStats()
    }

    func reload() {
        sources.removeAll()
        reloadToken = UUID()
        refreshStats()
    }

    func clear(caches: ImagePipeline.Cache.Caches) {
        pipeline.cache.removeAll(caches: caches)
        if caches.contains(.disk), kind == .urlCache {
            // `ImagePipeline.Cache` doesn't manage `URLCache`: it belongs to
            // the URL loading system.
            DataLoader.sharedUrlCache.removeAllCachedResponses()
        }
        reload()
    }

    func refreshStats() {
        let cache = pipeline.configuration.imageCache as? ImageCache
        memorySize = cache.map { "\(demoByteCount($0.totalCost)) · \($0.totalCount) images" } ?? "–"

        switch kind {
        case .urlCache:
            diskSize = demoByteCount(DataLoader.sharedUrlCache.currentDiskUsage)
        case .dataCache:
            guard let dataCache else {
                diskSize = "–"
                return
            }
            // Reading the size of the cache hits the disk, so it's done off
            // the main thread.
            Task.detached { [weak self, dataCache] in
                let size = dataCache.totalSize
                let count = dataCache.totalCount
                await MainActor.run {
                    self?.diskSize = "\(demoByteCount(size)) · \(count) files"
                }
            }
        }
    }
}
