// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import os
import SwiftUI

/// Demonstrates a decoder of an app's own: ``NukePixDecoder``, for NukePix, a
/// toy format no system framework reads, registered in
/// ``ImageDecoderRegistry``.
///
/// ```swift
/// let token = ImageDecoderRegistry.shared.register(NukePixDecoder.init)
/// ImageDecoderRegistry.shared.unregister(token)
/// ```
///
/// The registry asks its decoders newest first, and each one takes the data
/// or passes from its first bytes. The screen loads three files twice, first
/// with the decoder out of the registry and then in it: a NukePix file, which
/// `ImageDecoders.Default` can't read and the new decoder can; the same file
/// cut short, which the new decoder takes by its signature and then fails;
/// and a PNG, which it passes on to the default.
///
/// The decoder is registered in the shared registry, the one every pipeline
/// asks by default, but only while the screen is on display: Image Formats
/// and the Fixture Zoo ask the same registry and report the decoder each file
/// went to. The screen's pipeline has a delegate that asks the registry the
/// way the default one does and writes down the answer, and a memory cache of
/// its own, which each pass empties first: a memory cache hit asks no
/// decoder.
struct CustomDecoderDemo: View {
    @State private var model = CustomDecoderDemoModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CustomDecoderRegistryView(model: model)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)], alignment: .leading, spacing: 28) {
                    ForEach(CustomDecoderFile.allCases) { file in
                        CustomDecoderTile(file: file, model: model)
                    }
                }
                Text("Each run loads the three files twice, one after the other: first with `NukePixDecoder` out of the registry, then in it. The screen's memory cache is emptied before each pass, because an image served from memory asks no decoder. The NukePix files come from the fixture loader, online and offline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                seeAlso
            }
            .padding(16)
        }
        .onAppear { model.appear() }
        .onDisappear { model.disappear() }
        .demoInfo(Self.info)
    }

    private var seeAlso: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("See Also")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            ForEach([DemoScreen.imageFormats, .video]) { screen in
                Divider()
                NavigationLink(value: DemoRoute.screen(screen)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(screen.title)
                                .foregroundStyle(.primary)
                            Text(screen.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
            }
        }
    }

    private static let info = DemoInfo(
        "Custom Decoder",
        "Nuke decodes whatever Image I/O reads. For anything else – AVIF on a system without it, a format of your own – register a decoder. The registry asks the newest one first; each looks at the first bytes of the data and takes it or passes. NukePix is a toy format made up for this screen, and `NukePixDecoder` is registered only while the screen is open.",
        code: """
        // At launch
        ImageDecoderRegistry.shared.register(NukePixDecoder.init)

        struct NukePixDecoder: ImageDecoding {
            static let signature = Data("NUKE".utf8)
            static let type = AssetType(rawValue: "com.github.kean.nukepix")

            // Takes the data or passes, from its first bytes.
            init?(context: ImageDecodingContext) {
                guard context.data.starts(with: Self.signature) else {
                    return nil
                }
            }

            // On the pipeline's actor: it takes microseconds.
            var isAsynchronous: Bool { false }

            func decode(_ data: Data) throws -> ImageContainer {
                let bytes = [UInt8](data)
                guard bytes.count >= 8 else {
                    throw Error.missingPixels(expected: 1, found: 0)
                }
                guard bytes[4] == 1 else {
                    throw Error.unsupportedVersion(bytes[4])
                }
                let width = Int(bytes[5])
                let height = Int(bytes[6])
                let colorCount = Int(bytes[7])
                let runs = 8 + colorCount * 4
                guard bytes.count >= runs else {
                    throw Error.missingPixels(expected: width * height, found: 0)
                }

                // A length and a color, row by row.
                var pixels = [UInt8]()
                pixels.reserveCapacity(width * height * 4)
                var offset = runs
                while offset + 1 < bytes.count, pixels.count < width * height * 4 {
                    let length = Int(bytes[offset])
                    let color = Int(bytes[offset + 1])
                    guard color < colorCount else {
                        throw Error.colorOutOfRange(color)
                    }
                    let rgba = bytes[(8 + color * 4)..<(12 + color * 4)]
                    for _ in 0..<length {
                        pixels.append(contentsOf: rgba)
                    }
                    offset += 2
                }
                guard width > 0, height > 0, pixels.count == width * height * 4 else {
                    throw Error.missingPixels(expected: width * height, found: pixels.count / 4)
                }

                guard let provider = CGDataProvider(data: Data(pixels) as CFData),
                      let image = CGImage(
                        width: width,
                        height: height,
                        bitsPerComponent: 8,
                        bitsPerPixel: 32,
                        bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                        provider: provider,
                        decode: nil,
                        shouldInterpolate: false,
                        intent: .defaultIntent
                      ) else {
                    throw Error.missingPixels(expected: width * height, found: 0)
                }
                return ImageContainer(image: UIImage(cgImage: image), type: Self.type)
            }

            enum Error: Swift.Error {
                case unsupportedVersion(UInt8)
                case missingPixels(expected: Int, found: Int)
                case colorOutOfRange(Int)
            }
        }
        """,
        points: [
            .init("The format", "NukePix: the four bytes `NUKE`, a version, the width and height, a palette of RGBA colors, and then runs of pixels, each a length and a color. The badge is 56×26: 1,456 pixels in 874 bytes. The first bytes of each file are on the screen, next to what Image I/O makes of them: nothing."),
            .init("Registering", "`register(_:)` returns a token, and `unregister(_:)` takes the decoder out again. An app registers its decoders once, at launch. This screen registers `NukePixDecoder` when it appears and unregisters it when it goes, so Image Formats and the Fixture Zoo, which ask the same registry, report the decoders they did before. A pipeline that shouldn't ask the shared registry at all can set `ImagePipeline.Configuration.makeImageDecoder` to a registry of its own."),
            .init("The pick", "The pipeline asks its delegate for a decoder once the data is in, and the default delegate asks the registry. The registry creates each decoder with an `ImageDecodingContext` – the data, the request, and the response – newest first, and the first that doesn't return `nil` decodes the data. The signature decides, not the MIME type or the file name. For the formats Nuke knows, `AssetType(data)` reads the signature."),
            .init("Falling through", "`ImageDecoders.Default` is the registry's own first decoder, so it is asked last, and it takes any data: a pipeline always gets a decoder. The PNG shows that path with `NukePixDecoder` in place. Without it, the NukePix file goes the same way, and Image I/O can't read it: `decodingFailed`, with `ImageDecodingError.unknown`."),
            .init("Taken is final", "The file that was cut short still starts with the signature, so `NukePixDecoder` takes it, and its error is the result: the pipeline doesn't try the next decoder when `decode(_:)` throws. The error reaches the app as the `error` of `ImagePipeline.Error.decodingFailed`, next to the decoder and the context."),
            .init("Previews", "The initializer doesn't look at `context.isCompleted`. With progressive decoding on, the pipeline asks as soon as the first bytes arrive, and keeps the decoder it gets for the whole download: a decoder that passes on a partial file hands all of it to `ImageDecoders.Default`. A decoder with no previews to offer takes the data and leaves `decodePartiallyDownloadedData(_:)` to its default, which returns `nil`."),
            .init("Where it runs", "`isAsynchronous` is `true` by default, which puts every decode on the pipeline's decoding queue. `NukePixDecoder` says `false`, and decodes on the pipeline's actor, which suits work that takes microseconds. A real codec should stay on the queue."),
            .init("The container", "`type` is an `AssetType` of the decoder's own. A decoder whose images are drawn by something else – an animation, a video, a vector format – also puts the data in `data`, and anything else in `userInfo`. The pipeline decompresses the image and caches it like any other."),
            .init("Plug-ins", "The community decoders listed in Nuke's README – NukeWebP and the WebP Plugin, from before Image I/O read WebP, and the AVIF Plugin – are this shape: a decoder around a codec library, and a line that registers it. BlurHash has no file to download: an `ImageRequest(id:image:)` closure can decode the hash, or a decoder can recognise the request by its `userInfo`, which the context carries."),
            .init("Decode time", "Measured by the demo's pipeline probe, which wraps the decoder the registry returns, as the pipeline HUD shows it. A decode that throws has no time.")
        ]
    )
}

extension NukePixDecoder: DemoSynchronousDecoding {}

// MARK: - Registry

/// The registry's decoders in the order it asks them, and the run.
private struct CustomDecoderRegistryView: View {
    let model: CustomDecoderDemoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ImageDecoderRegistry.shared")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("Asked newest first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                row(1, "NukePixDecoder", model.isRegistered ? "registered by this screen" : "not registered", isActive: model.isRegistered)
                row(2, "ImageDecoders.Video", "registered by the app at launch")
                row(3, "ImageDecoders.Default", "the registry's own: takes any data")
            }
            HStack(spacing: 12) {
                DemoMonoLabel(model.status, tint: model.isRunning ? .orange : .secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button("Run Again", systemImage: "arrow.clockwise") {
                    model.runAgain()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ number: Int, _ decoder: String, _ note: String, isActive: Bool = true) -> some View {
        GridRow {
            Text("\(number)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(decoder)
                    .font(.system(.footnote, design: .monospaced))
                    .strikethrough(!isActive)
                    .foregroundStyle(isActive ? .primary : .secondary)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(isActive ? Color.secondary : Color.orange)
            }
        }
    }
}

// MARK: - Tile

/// The files the screen loads.
private enum CustomDecoderFile: CaseIterable, Identifiable {
    case badge
    case truncated
    case png

    var id: Self { self }

    var title: String {
        switch self {
        case .badge: "NukePix"
        case .truncated: "NukePix, Cut Short"
        case .png: "PNG"
        }
    }

    var caption: String {
        switch self {
        case .badge: "The signature, a palette, and 1,456 pixels in runs"
        case .truncated: "The same file with its last 40% missing"
        case .png: "Any other file: NukePixDecoder passes"
        }
    }

    /// The URL, read when a run starts: the PNG is a fixture's while the demo
    /// is offline.
    var url: URL {
        switch self {
        case .badge: DemoFixture.nukePix.url
        case .truncated: DemoFixture.truncatedNukePix.url
        case .png: DemoImages.png
        }
    }

    /// Whether the image is pixel art, drawn without smoothing.
    var isPixelArt: Bool {
        self != .png
    }
}

/// A file, what it starts with, and what each pass made of it.
private struct CustomDecoderTile: View {
    let file: CustomDecoderFile
    let model: CustomDecoderDemoModel

    var body: some View {
        DemoExample(file.title, caption: file.caption) {
            VStack(alignment: .leading, spacing: 12) {
                CustomDecoderFileFigures(figures: model.files[file])
                HStack(alignment: .top, spacing: 12) {
                    ForEach(CustomDecoderPass.allCases) { pass in
                        CustomDecoderPane(file: file, pass: pass, outcome: model.outcomes[file]?[pass], isLoading: model.isLoading(file, pass))
                    }
                }
            }
        }
    }
}

/// What the file is: its first bytes, how it was served, and what Image I/O
/// reads in it.
private struct CustomDecoderFileFigures: View {
    let figures: CustomDecoderDemoModel.FileFigures?

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 3) {
            row("bytes", figures.map { Self.hex($0.firstBytes) } ?? "–", tint: .primary)
            row("served", figures.map { "\($0.mimeType ?? "no MIME type") · \(demoByteCount($0.byteCount))" } ?? "–")
            row("Image I/O", imageIO)
        }
    }

    private func row(_ title: String, _ value: String, tint: Color? = nil) -> some View {
        GridRow {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            DemoMonoLabel(value, tint: tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var imageIO: String {
        guard let figures else { return "–" }
        guard let header = figures.header else { return "reading…" }
        guard let width = header.width, let height = header.height else {
            return header.typeSummary
        }
        return "\(header.typeSummary) · \(width)×\(height)"
    }

    /// "4E 55 4B 45 01 38 1A 36  NUKE·8·6": the bytes, then the ones that
    /// are printable as ASCII.
    private static func hex(_ bytes: Data) -> String {
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let text = String(bytes.map { (0x21...0x7E).contains($0) ? Character(UnicodeScalar($0)) : "·" })
        return "\(hex)  \(text)"
    }
}

/// One pass over a file: the image, or the failure, and the decoder the
/// registry picked.
private struct CustomDecoderPane: View {
    let file: CustomDecoderFile
    let pass: CustomDecoderPass
    let outcome: CustomDecoderDemoModel.Outcome?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pass.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            ZStack {
                Color(.secondarySystemBackground)
                image
            }
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    DemoMonoLabel(line.text, tint: line.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var image: some View {
        switch outcome?.result {
        case .success(let response):
            Image(uiImage: response.image)
                .resizable()
                .interpolation(file.isPixelArt ? .none : .high)
                .scaledToFit()
                .padding(file.isPixelArt ? 12 : 0)
        case .failure:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case nil:
            if isLoading {
                ProgressView()
            }
        }
    }

    /// The decoder, what came of it, and how long it took.
    private var lines: [(text: String, tint: Color?)] {
        guard let outcome else {
            return [("–", nil), (" ", nil), (" ", nil)]
        }
        let decoder: (text: String, tint: Color?) = (outcome.decoder ?? "no decoder", .primary)
        switch outcome.result {
        case .success(let response):
            let size = response.image.cgImage.map { "\($0.width)×\($0.height)" } ?? "–"
            let time = outcome.decodeDuration.map { " · \(demoMilliseconds($0))" } ?? ""
            return [decoder, (Self.literal(response.container.type), nil), (size + time, nil)]
        case .failure(let error):
            let summary = Self.summary(of: error)
            return [decoder, (summary.title, .red), (summary.detail, .red)]
        }
    }

    /// `.png`, or the raw value of a type Nuke doesn't name.
    private static func literal(_ type: AssetType?) -> String {
        guard let type, type == NukePixDecoder.type else {
            return type.demoLiteral
        }
        return "\"\(type.rawValue)\""
    }

    /// The error's case, and what it wraps.
    private static func summary(of error: ImagePipeline.Error) -> (title: String, detail: String) {
        switch error {
        case let .decodingFailed(_, _, underlying):
            if let underlying = underlying as? ImageDecodingError, case .unknown = underlying {
                return ("decodingFailed · threw", "ImageDecodingError.unknown")
            }
            if case let .missingPixels(expected, found)? = underlying as? NukePixDecoder.Error {
                return ("decodingFailed · threw", "missingPixels: \(found) of \(expected.formatted())")
            }
            return ("decodingFailed · threw", "\(underlying)")
        case .dataLoadingFailed(let underlying):
            if let underlying = underlying as? URLError {
                return ("dataLoadingFailed", "URLError \(underlying.code.rawValue)")
            }
            return ("dataLoadingFailed", "\(underlying)")
        case .decoderNotRegistered:
            return ("decoderNotRegistered", "no decoder took the data")
        default:
            return ("\(error)", " ")
        }
    }
}

/// A pass over the files, with the decoder out of the registry or in it.
private enum CustomDecoderPass: CaseIterable, Identifiable {
    case without
    case with

    var id: Self { self }

    var title: String {
        switch self {
        case .without: "Without NukePixDecoder"
        case .with: "With NukePixDecoder"
        }
    }
}

// MARK: - Model

/// Registers the decoder while the screen is on display, and runs the two
/// passes.
@MainActor @Observable
private final class CustomDecoderDemoModel {
    /// Whether ``NukePixDecoder`` is in the shared registry now.
    private(set) var isRegistered = false
    private(set) var files: [CustomDecoderFile: FileFigures] = [:]
    private(set) var outcomes: [CustomDecoderFile: [CustomDecoderPass: Outcome]] = [:]
    private(set) var isRunning = false
    /// The pass and the file being loaded.
    private(set) var current: (pass: CustomDecoderPass, file: CustomDecoderFile)?
    private(set) var runCount = 0

    @ObservationIgnored private var token: ImageDecoderRegistry.RegistrationToken?
    @ObservationIgnored private var isOnScreen = false
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private let picks = DecoderPickLog()
    /// Made when the screen first appears, not in `init`: SwiftUI makes a
    /// model each time it makes the view, and keeps only the first.
    @ObservationIgnored private lazy var pipeline: ImagePipeline = {
        // `URLCache` for the PNG, as the shared pipeline has, and a memory
        // cache of the screen's own, which each pass empties.
        var configuration = ImagePipeline.Configuration.withURLCache
        configuration.imageCache = ImageCache()
        return DemoPipelineProbe.makePipeline("Custom Decoder", configuration: configuration, delegate: DecoderPickWatcher(picks: picks))
    }()

    /// What a file is, from the first pass that loaded it.
    struct FileFigures {
        let firstBytes: Data
        let mimeType: String?
        let byteCount: Int
        var header: DemoImageHeader?
    }

    /// What a pass made of a file.
    struct Outcome {
        /// The decoder the registry picked, or `nil` if none took the data.
        let decoder: String?
        let result: Result<ImageResponse, ImagePipeline.Error>
        /// How long the decode took, as the probe measured it; `nil` for a
        /// decode that threw.
        let decodeDuration: TimeInterval?
    }

    var status: String {
        if let current {
            return "run \(runCount) · \(current.pass == .without ? "without" : "with") NukePixDecoder · \(current.file.title)…"
        }
        guard runCount > 0 else {
            return "not run yet"
        }
        return "run \(runCount) · without the decoder, then with it"
    }

    func isLoading(_ file: CustomDecoderFile, _ pass: CustomDecoderPass) -> Bool {
        isRunning && outcomes[file]?[pass] == nil
    }

    func appear() {
        isOnScreen = true
        setRegistered(true)
        runAgain()
    }

    func disappear() {
        isOnScreen = false
        runTask?.cancel()
        runTask = nil
        setRegistered(false)
    }

    /// Cancels the run in progress, if any, and starts a new one once it has
    /// stopped, so two runs never take turns with the registry.
    func runAgain() {
        let previous = runTask
        previous?.cancel()
        runTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await run()
        }
    }

    private func setRegistered(_ isRegistered: Bool) {
        if isRegistered, token == nil {
            token = ImageDecoderRegistry.shared.register(NukePixDecoder.init)
        } else if !isRegistered, let token {
            ImageDecoderRegistry.shared.unregister(token)
            self.token = nil
        }
        self.isRegistered = token != nil
    }

    private func run() async {
        runCount += 1
        // The PNG is another file once the demo goes offline.
        files = [:]
        outcomes = [:]
        isRunning = true
        defer {
            isRunning = false
            current = nil
            setRegistered(isOnScreen)
        }
        for pass in CustomDecoderPass.allCases {
            guard !Task.isCancelled else { return }
            // Only while the screen is on display, even mid-run.
            setRegistered(pass == .with && isOnScreen)
            pipeline.cache.removeAll(caches: .memory)
            for file in CustomDecoderFile.allCases {
                guard !Task.isCancelled else { return }
                current = (pass, file)
                let outcome = await load(file)
                guard !Task.isCancelled else { return }
                outcomes[file, default: [:]][pass] = outcome
            }
        }
    }

    /// Loads a file, one at a time, so the probe's last decode is this one's.
    private func load(_ file: CustomDecoderFile) async -> Outcome {
        let id = UUID()
        var request = ImageRequest(url: file.url)
        request.userInfo[DecoderPickWatcher.loadKey] = id
        let decodes = DemoPipelineProbe.diagnostics(for: pipeline)?.decoding.count ?? 0

        let result: Result<ImageResponse, ImagePipeline.Error>
        do throws(ImagePipeline.Error) {
            result = .success(try await pipeline.imageTask(with: request).response)
        } catch {
            result = .failure(error)
        }

        let decoding = DemoPipelineProbe.diagnostics(for: pipeline)?.decoding
        let decodeDuration = decoding.flatMap { $0.count == decodes + 1 ? $0.last : nil }
        let pick = picks.take(id)
        if let pick, files[file] == nil {
            files[file] = FileFigures(firstBytes: pick.data.prefix(8), mimeType: pick.mimeType, byteCount: pick.data.count)
            let header = await DemoImageHeader.read(pick.data)
            files[file]?.header = header
        }
        return Outcome(decoder: pick?.decoder, result: result, decodeDuration: result.isSuccess ? decodeDuration : nil)
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { true } else { false }
    }
}

// MARK: - Watcher

/// What the pipeline had in hand when it asked for a decoder, and what it
/// got.
private struct DecoderPick: Sendable {
    /// The decoder's type, or `nil` if no decoder took the data.
    let decoder: String?
    let mimeType: String?
    let data: Data
}

/// The picks, by the load they were made for, until the screen takes them.
private final class DecoderPickLog: Sendable {
    private let picks = OSAllocatedUnfairLock(initialState: [UUID: DecoderPick]())

    func record(_ pick: DecoderPick, for id: UUID) {
        picks.withLock { $0[id] = pick }
    }

    func take(_ id: UUID) -> DecoderPick? {
        picks.withLock { $0.removeValue(forKey: id) }
    }
}

/// Asks for a decoder the way the default delegate does, and writes down
/// what it got.
///
/// The pipeline asks on its own threads once the data is complete, before
/// the decode, so the pick is in the log by the time the load's response
/// arrives.
private final class DecoderPickWatcher: ImagePipeline.Delegate {
    /// The key of the load a request belongs to, in its `userInfo`.
    static let loadKey: ImageRequest.UserInfoKey = "com.github.kean.NukeDemo.CustomDecoder.load"

    private let picks: DecoderPickLog

    init(picks: DecoderPickLog) {
        self.picks = picks
    }

    func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> (any ImageDecoding)? {
        // The default: the configuration's factory, which asks
        // `ImageDecoderRegistry.shared`.
        let decoder = pipeline.configuration.makeImageDecoder(context)
        if context.isCompleted, let id = context.request.userInfo[Self.loadKey] as? UUID {
            let pick = DecoderPick(decoder: decoder.map { demoTypeName(of: $0) }, mimeType: context.urlResponse?.mimeType, data: context.data)
            picks.record(pick, for: id)
        }
        return decoder
    }
}
