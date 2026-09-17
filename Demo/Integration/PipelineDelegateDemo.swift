// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI

/// Demonstrates ``ImagePipeline/Delegate-swift.protocol``: a delegate that
/// adds a header to the URL requests, leaves a token out of the cache key, and
/// keeps a private photo off the disk, with a log of what it is asked.
///
/// ```swift
/// let pipeline = ImagePipeline(delegate: DemoPipelineDelegate()) {
///     $0.dataCache = try? DataCache(name: "com.example.images")
/// }
/// ```
///
/// The log comes from the probe every demo pipeline has: the probe is the
/// pipeline's delegate, passes every call on to the screen's, and reports what
/// it returned (see ``DemoPipelineProbe/Event``).
struct PipelineDelegateDemo: View {
    @StateObject private var model = PipelineDelegateDemoModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(model.photos) { photo in
                    // In an overlay, so that the width of the photo doesn't
                    // take part in the layout and the tiles come out equal.
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 90)
                        .overlay {
                            LazyImage(request: photo.request) { state in
                                if let image = state.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    DemoPlaceholder()
                                }
                            }
                            .pipeline(model.pipeline)
                            .onCompletion { model.didComplete(photo, $0) }
                        }
                        .clipped()
                        .overlay(alignment: .topTrailing) {
                            if photo.isPrivate {
                                DemoBadge("Private", color: .purple)
                                    .padding(4)
                            }
                        }
                        .overlay(alignment: .bottomLeading) {
                            if let source = model.sources[photo.id] {
                                DemoBadge(source.title, color: source.color)
                                    .padding(4)
                            }
                        }
                }
            }
            .id(model.reloadToken)

            HStack(spacing: 8) {
                Button("Reload", systemImage: "arrow.clockwise") { model.reload() }
                Button("Clear Memory") { model.clear(caches: [.memory]) }
                Button("Clear All", role: .destructive) { model.clear(caches: [.all]) }
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.top, 10)

            PipelineEventLogView(log: model.log)
        }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Pipeline Delegate",
        "`ImagePipeline.Delegate` customizes the pipeline per request. The one on this screen adds a header in `willLoadData`, leaves the token out of the cache key, and keeps the private photo off the disk. The log lists what the delegate is asked, newest first.",
        code: """
        final class MyPipelineDelegate: ImagePipeline.Delegate {
            func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
                var urlRequest = urlRequest
                urlRequest.setValue("Bearer \\(try await token())", forHTTPHeaderField: "Authorization")
                return urlRequest
            }

            func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
                request.url.map(removingToken)
            }

            func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline) async -> Data? {
                isPrivate(request) ? nil : data
            }
        }
        """,
        points: [
            .init("Per request", "Every callback receives the `ImageRequest`, so the delegate can treat avatars differently from photos."),
            .init("willLoadData", "`willLoadData(for:urlRequest:pipeline:)` hands you the `URLRequest` before it is sent and takes back the one to use. It is async and throwing, so it can wait for a token to be refreshed, and throwing from it fails the request. This one adds an `X-Nuke-Demo` header."),
            .init("cacheKey", "A server that signs its URLs hands out a new `token` with every one – here, on every reload. `cacheKey(for:pipeline:)` leaves the token out, so the new URL finds what the old one cached. The key replaces the default one in both caches, and the pipeline asks for it on every read and write: the count on its row. For a single request, `ImageRequest.imageID` does the same."),
            .init("willCache", "`willCache(data:image:for:pipeline:)` is asked before every write to the disk cache, with the data, and returns what to store: the data, something else – encrypted, say – or `nil` for nothing. The private photo never reaches the disk, though it stays in the memory cache, which `willCache` isn't asked about."),
            .init("Events", "`imageTask(_:didReceiveEvent:pipeline:)` reports the progress, the previews, and the outcome of every task. The log keeps the last progress event of each."),
            .init("Memory hits", "A view that finds its image in the memory cache shows it without starting a task, so the delegate hears only the cache key being asked for."),
            .init("Try it", "The screen starts with both caches empty. The badge on each photo says where it came from: Reload is served from memory, Clear Memory from the disk – all but the private photo – and Clear All from the network.")
        ]
    )
}

private struct PipelineEventLogView: View {
    @ObservedObject var log: PipelineEventLog

    var body: some View {
        List {
            Section {
                if log.rows.isEmpty {
                    Text("No calls yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(log.rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.title)
                                .font(.footnote.weight(.medium))
                            Spacer()
                            if row.count > 1 {
                                DemoMonoLabel("×\(row.count)")
                            }
                        }
                        Text(row.subtitle)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Delegate Calls")
            }
        }
        .listStyle(.plain)
    }
}

@MainActor
private final class PipelineDelegateDemoModel: ObservableObject {
    struct Photo: Identifiable {
        let id: Int
        let request: ImageRequest

        var isPrivate: Bool {
            request.userInfo[.isPrivateKey] as? Bool ?? false
        }
    }

    struct Source {
        let title: String
        let color: Color
    }

    let log: PipelineEventLog
    let pipeline: ImagePipeline

    @Published private(set) var photos: [Photo] = []
    @Published private(set) var sources: [Photo.ID: Source] = [:]
    @Published private(set) var reloadToken = UUID()

    /// The tokens handed out so far.
    private var tokenCount: UInt16 = 0

    init() {
        let log = PipelineEventLog()
        self.log = log

        // A memory cache of the screen's own, and a disk cache emptied on the
        // way in, so that the first load goes through every hook.
        var configuration = ImagePipeline.Configuration.withDataCache(name: "com.github.kean.NukeDemo.PipelineDelegate")
        configuration.imageCache = ImageCache()
        configuration.dataCache?.removeAll()

        // The probe every demo pipeline has sits in front of the delegate: it
        // passes every call on and reports what the delegate returned. The
        // handler is called on the pipeline's threads, so it only hands off.
        self.pipeline = DemoPipelineProbe.makePipeline(
            "Pipeline Delegate",
            configuration: configuration,
            delegate: DemoPipelineDelegate(),
            onEvent: { event in
                Task { @MainActor in log.append(event) }
            }
        )
        photos = Self.makePhotos(token: makeToken())
    }

    func didComplete(_ photo: Photo, _ result: Result<ImageResponse, ImagePipeline.Error>) {
        guard case .success(let response) = result else { return }
        sources[photo.id] = switch response.cacheType {
        case .memory?: Source(title: "Memory", color: .green)
        case .disk?: Source(title: "Disk", color: .blue)
        case nil: Source(title: "Network", color: .orange)
        }
    }

    func reload() {
        log.removeAll()
        sources.removeAll()
        photos = Self.makePhotos(token: makeToken())
        reloadToken = UUID()
    }

    func clear(caches: ImagePipeline.Cache.Caches) {
        pipeline.cache.removeAll(caches: caches)
        reload()
    }

    /// A new token for every load: random, or counted under
    /// `-demoDeterministic 1`, so that the log reads the same every launch.
    private func makeToken() -> String {
        tokenCount &+= 1
        let value = DemoLaunchOptions.current.isDeterministic ? tokenCount : UInt16.random(in: .min ... .max)
        return String(format: "%04X", value)
    }

    /// The photos as a server that signs its URLs hands them out: with a new
    /// token every time. The last one is from a private album.
    private static func makePhotos(token: String) -> [Photo] {
        DemoImages.photos.prefix(4).enumerated().map { index, url in
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "token", value: token)]
            var request = ImageRequest(url: components?.url)
            if index == 3 {
                request.userInfo[.isPrivateKey] = true
            }
            return Photo(id: index, request: request)
        }
    }
}

/// The delegate an app would write: it authenticates the requests, keeps the
/// cache key the same from one signed URL to the next, and keeps private photos
/// off the disk.
///
/// `willLoadData` and `willCache` run on ``ImagePipelineActor``; `cacheKey` is
/// called from any thread, the main one included. The delegate keeps no state,
/// so it has nothing to guard.
private final class DemoPipelineDelegate: ImagePipeline.Delegate {
    @ImagePipelineActor
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        var urlRequest = urlRequest
        // This is where an app injects an authorization token or signs the
        // request. Throwing from here fails the request.
        urlRequest.setValue("nuke-demo", forHTTPHeaderField: "X-Nuke-Demo")
        return urlRequest
    }

    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        // The key replaces the default one, which also tells requests apart by
        // their processors and thumbnail. This one doesn't, so a request with
        // either keeps the default key.
        guard request.processors.isEmpty, request.thumbnail == nil,
              let url = request.url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        // The token changes every time the URL is signed; the image doesn't.
        components.queryItems?.removeAll { $0.name == "token" }
        if components.queryItems?.isEmpty == true {
            components.queryItems = nil
        }
        return components.string
    }

    @ImagePipelineActor
    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline) async -> Data? {
        // This is where an app encrypts what it stores. A private photo isn't
        // stored at all.
        request.userInfo[.isPrivateKey] as? Bool == true ? nil : data
    }
}

extension ImageRequest.UserInfoKey {
    /// Marks a request for a photo that mustn't be written to the disk.
    fileprivate static let isPrivateKey: ImageRequest.UserInfoKey = "com.github.kean.NukeDemo.isPrivate"
}

/// The calls the delegate is asked, newest first. Being `@MainActor` makes it
/// `Sendable`, which is what lets the probe's event handler capture it.
@MainActor
private final class PipelineEventLog: ObservableObject {
    struct Row: Identifiable {
        let id: Int
        let title: String
        let subtitle: String
        /// The calls the row stands for.
        var count = 1
    }

    @Published private(set) var rows: [Row] = []

    private var nextID = 0
    /// The row that stands for every `cacheKey` call of a request, by URL.
    private var cacheKeyRows: [URL: Row.ID] = [:]

    func append(_ event: DemoPipelineProbe.Event) {
        let url = event.request.url
        let name = Self.name(of: url)
        switch event.kind {
        case .cacheKey(let key):
            // Asked on every read and write of either cache: a row each would
            // bury the rest, so a request gets one, with a count.
            if let url, let id = cacheKeyRows[url], let index = rows.firstIndex(where: { $0.id == id }) {
                rows[index].count += 1
                return
            }
            let returned = key.map { Self.name(of: URL(string: $0), withQuery: true) } ?? "default key"
            let id = insert("cacheKey", "\(Self.name(of: url, withQuery: true)) → \(returned)")
            if let url {
                cacheKeyRows[url] = id
            }
        case .willLoadData(let urlRequest):
            let headers = (urlRequest.allHTTPHeaderFields ?? [:])
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
            insert("willLoadData", ([name] + headers).joined(separator: " · "))
        case let .willCache(byteCount, isEncodedImage, storedByteCount):
            let data = demoByteCount(byteCount) + (isEncodedImage ? " encoded" : "")
            let returned = switch storedByteCount {
            case nil: "nil, not stored"
            case byteCount?: "stored"
            case let count?: "\(demoByteCount(count)) stored"
            }
            insert("willCache", "\(name) · \(data) → \(returned)")
        case .imageTaskDidStart:
            insert("imageTaskDidStart", name)
        case .progress(let progress):
            insert("didReceiveEvent(.progress)", "\(name) · \(demoByteCount(progress.total))")
        case .preview:
            insert("didReceiveEvent(.preview)", name)
        case .finished(.success(let response)):
            let source = switch response.cacheType {
            case .memory?: "memory"
            case .disk?: "disk"
            case nil: "network"
            }
            insert("didReceiveEvent(.finished)", "\(name) · \(source)")
        case .finished(.failure(let error)):
            insert("didReceiveEvent(.finished)", "\(name) · \(error)")
        }
    }

    func removeAll() {
        rows.removeAll()
        cacheKeyRows.removeAll()
    }

    @discardableResult
    private func insert(_ title: String, _ subtitle: String) -> Row.ID {
        nextID += 1
        rows.insert(Row(id: nextID, title: title, subtitle: subtitle), at: 0)
        if rows.count > 50 {
            rows.removeLast(rows.count - 50)
        }
        return nextID
    }

    /// The file name of a photo, cut short – `ecb16e82….jpg` – and its query
    /// when asked for, which is where the token is.
    private static func name(of url: URL?, withQuery: Bool = false) -> String {
        guard let url else { return "–" }
        let stem = url.deletingPathExtension().lastPathComponent
        var name = stem.count > 8 ? "\(stem.prefix(8))…" : stem
        if !url.pathExtension.isEmpty {
            name += ".\(url.pathExtension)"
        }
        if withQuery, let query = url.query() {
            name += "?\(query)"
        }
        return name
    }
}
