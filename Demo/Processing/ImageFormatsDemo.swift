// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI

/// Demonstrates the image formats that Nuke decodes out of the box, and how
/// the pipeline tells them apart.
///
/// A request doesn't say what format to expect. Once the data is in, the
/// pipeline asks its delegate for a decoder, and the default delegate asks
/// ``ImageDecoderRegistry``, whose decoders each look at the data and take it
/// or pass. Under every image is what came of that: the type the server sent,
/// the ``AssetType`` the decoder read in the data, the decoder that took it,
/// and, for a second opinion, what Image I/O reads in the file.
///
/// The screen's pipeline has a delegate that asks the registry the way the
/// default one does and writes down the answer (``DecoderWatcher``). It has a
/// memory cache of its own, so every visit decodes the files again, from
/// `URLCache` after the first.
///
/// Video, the other decoder the app registers, has a screen of its own,
/// ``VideoDemo``. ``AnimatedImagesDemo`` shows what NukeUI does with the
/// animated formats.
struct ImageFormatsDemo: View {
    @State private var model = ImageFormatsDemoModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], alignment: .leading, spacing: 24) {
                    ForEach(ImageFormat.allCases) { format in
                        ImageFormatTile(format: format, model: model)
                    }
                }
                Text("Under each image: the MIME type the server sent and the size of the data; `ImageContainer.type`, the format the decoder read in the data, and the frames it kept the data for; the decoder `ImageDecoderRegistry` gave the data to; and what Image I/O reads in the file's header.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Image Formats",
        "Nuke decodes with Image I/O, which reads JPEG, PNG, WebP, HEIF, GIF, and more. Nothing in a request names the format: the pipeline picks a decoder from the data itself, and each image here shows what it found.",
        code: """
        // What the default delegate does
        func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> (any ImageDecoding)? {
            ImageDecoderRegistry.shared.decoder(for: context)
        }

        // Adding a format
        ImageDecoderRegistry.shared.register(MyDecoder.init)
        """,
        points: [
            .init("The registry", "`ImageDecoderRegistry` starts with `ImageDecoders.Default`, which takes any data, and asks the decoders registered after it first, newest first. Each is created with an `ImageDecodingContext` – the data, the request, and the response – and returns `nil` for data it can't decode. The app registers `ImageDecoders.Video` at launch, which passes on anything but MP4 and QuickTime files, so every image here goes to the default decoder."),
            .init("The type", "`ImageContainer.type` is the `AssetType` the decoder read in the first bytes of the data: a signature, and for HEIF the brands in its `ftyp` box. Neither the file name nor the MIME type counts. A format Nuke doesn't name has a `nil` type, and decodes all the same."),
            .init("HEIC", "The photo is a HEIC as an iPhone camera writes it, led by the `heic` brand. A HEIF led by the bare `mif1` brand that names no codec after it has a `nil` type. Image I/O can also write HEIC: `ImageEncoders.Default.isHEIFPreferred` makes it the format of the images the pipeline stores on disk."),
            .init("Animated images", "For a GIF, and for a PNG, WebP, or HEIF whose header says it is animated, the container keeps the data next to the first frame, and NukeUI plays it. The APNG is served as `image/png` like any PNG, and its type is `.png`: the frames are what tell it apart. The Animated Images screen shows what playing them costs."),
            .init("Image I/O", "The last line is what `CGImageSource` reads in the file without decoding it: its type identifier, how many images it counts, and the size of the first."),
            .init("Video", "`ImageDecoders.Video`, from the NukeVideo module, has a screen of its own under Integration."),
            .init("Custom decoders", "Register one with `ImageDecoderRegistry` to add a format. Its initializer sees the data and decides whether it can decode it. The Custom Decoder screen registers one for a toy format."),
            .init("Decompression", "Nuke decompresses the image on a background queue so that the first draw does not stall the main thread. The Decompression screen counts the frames it saves.")
        ]
    )
}

// MARK: - Tile

private enum ImageFormat: CaseIterable, Identifiable {
    case jpeg
    case png
    case webp
    case heic
    case gif
    case apng

    var id: Self { self }

    var title: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .webp: "WebP"
        case .heic: "HEIC"
        case .gif: "Animated GIF"
        case .apng: "Animated PNG"
        }
    }

    var caption: String {
        switch self {
        case .jpeg: "Decoded and decompressed in the background"
        case .png: "Transparency is preserved"
        case .webp: "Supported natively since iOS 14"
        case .heic: "A photo as an iPhone camera writes it"
        case .gif: "state.animatedImage, played by NukeUI"
        case .apng: "The default LazyImage content plays animations on its own"
        }
    }

    var isAnimated: Bool {
        self == .gif || self == .apng
    }

    var url: URL {
        switch self {
        case .jpeg: DemoImages.landscape
        case .png: DemoImages.png
        case .webp: DemoImages.webp
        case .heic: DemoImages.heic
        case .gif: DemoImages.gif
        case .apng: DemoImages.apng
        }
    }
}

/// An image, and what the pipeline made of its data.
private struct ImageFormatTile: View {
    let format: ImageFormat
    let model: ImageFormatsDemoModel

    var body: some View {
        DemoExample(format.title, caption: format.caption) {
            VStack(alignment: .leading, spacing: 10) {
                image
                    .frame(height: format.isAnimated ? 240 : 200)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay {
                        if case .failure = model.results[format] {
                            DemoFailureView()
                        }
                    }
                ImageFormatFigures(choice: model.choice(for: format), result: model.results[format])
            }
        }
    }

    @ViewBuilder
    private var image: some View {
        let request = model.requests[format]
        switch format {
        case .gif:
            LazyImage(request: request) { state in
                if let animatedImage = state.animatedImage {
                    AnimatedImage(animatedImage).resizable().scaledToFill()
                } else if let image = state.image {
                    image.resizable().scaledToFill()
                } else {
                    DemoPlaceholder()
                }
            }
            .pipeline(model.pipeline)
            .onCompletion { model.didComplete(format, $0) }
        case .apng:
            LazyImage(request: request)
                .pipeline(model.pipeline)
                .onCompletion { model.didComplete(format, $0) }
        default:
            LazyImage(request: request) { state in
                if let image = state.image {
                    image.resizable().scaledToFit()
                } else {
                    DemoPlaceholder()
                }
            }
            .pipeline(model.pipeline)
            .onCompletion { model.didComplete(format, $0) }
        }
    }
}

/// Four lines: the response, the type, the decoder, and the header.
private struct ImageFormatFigures: View {
    let choice: DecoderChoice?
    let result: Result<ImageResponse, ImagePipeline.Error>?

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 3) {
            row("served", served)
            let type = type
            row("type", type.text, tint: type.tint)
            row("decoder", decoder)
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

    private var served: String {
        guard let choice else { return "–" }
        return "\(choice.mimeType ?? "no MIME type") · \(demoByteCount(choice.byteCount))"
    }

    /// What the response says: the type, and the frames of an animation.
    private var type: (text: String, tint: Color?) {
        switch result {
        case nil:
            return ("–", nil)
        case .success(let response):
            let container = response.container
            let frames = container.animation.map { "\($0.frameCount) frames" } ?? "still"
            return ("\(container.type.demoLiteral) · \(frames)", .primary)
        case .failure(let error):
            return ("failed · \(error.demoDetail)", .red)
        }
    }

    private var decoder: String {
        guard let choice else { return "–" }
        return choice.decoder ?? "none took the data"
    }

    private var imageIO: String {
        guard let choice else { return "–" }
        return choice.header?.summary ?? "reading…"
    }
}

// MARK: - Model

/// The screen's pipeline, a request per image, and what each came to.
@MainActor @Observable
private final class ImageFormatsDemoModel {
    /// Made the first time the screen asks rather than in `init`, which
    /// SwiftUI runs each time it makes the view, keeping only the first
    /// model.
    @ObservationIgnored private(set) lazy var pipeline = makePipeline()
    let requests: [ImageFormat: ImageRequest]
    private(set) var results: [ImageFormat: Result<ImageResponse, ImagePipeline.Error>] = [:]
    private let log: DecoderChoiceLog

    init() {
        log = DecoderChoiceLog()
        requests = Dictionary(uniqueKeysWithValues: ImageFormat.allCases.map { ($0, ImageRequest(url: $0.url)) })
    }

    private func makePipeline() -> ImagePipeline {
        // `URLCache`, as the shared pipeline has, and a memory cache of the
        // screen's own, so that every visit decodes the images again and the
        // delegate sees their data.
        var configuration = ImagePipeline.Configuration.withURLCache
        configuration.imageCache = ImageCache()
        return DemoPipelineProbe.makePipeline("Image Formats", configuration: configuration, delegate: DecoderWatcher(log: log))
    }

    func choice(for format: ImageFormat) -> DecoderChoice? {
        requests[format]?.url.flatMap { log.choices[$0] }
    }

    func didComplete(_ format: ImageFormat, _ result: Result<ImageResponse, ImagePipeline.Error>) {
        results[format] = result
    }
}

/// What the pipeline had in hand when it picked a decoder, and what it
/// picked.
private struct DecoderChoice {
    let id = UUID()
    /// The decoder's type, or `nil` if no decoder took the data.
    let decoder: String?
    let mimeType: String?
    let byteCount: Int
    /// Read after the pick, off the main thread.
    var header: DemoImageHeader?
}

/// The decoders picked, by URL: the last pick for each.
@MainActor @Observable
private final class DecoderChoiceLog {
    private(set) var choices: [URL: DecoderChoice] = [:]

    func record(_ choice: DecoderChoice, for url: URL, data: Data) {
        choices[url] = choice
        Task {
            let header = await DemoImageHeader.read(data)
            if choices[url]?.id == choice.id {
                choices[url]?.header = header
            }
        }
    }
}

/// Asks for a decoder the way the default delegate does, and tells the log
/// what it got.
///
/// The pipeline asks from its own threads once the data is complete, and
/// waits for the answer, so the delegate only hands the data on: Image I/O
/// reads the header later, out of the pipeline's way.
private final class DecoderWatcher: ImagePipeline.Delegate {
    private let log: DecoderChoiceLog

    init(log: DecoderChoiceLog) {
        self.log = log
    }

    func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> (any ImageDecoding)? {
        // The default: the configuration's factory, which asks
        // `ImageDecoderRegistry.shared`.
        let decoder = pipeline.configuration.makeImageDecoder(context)
        guard context.isCompleted, let url = context.request.url else {
            return decoder
        }
        let choice = DecoderChoice(
            decoder: decoder.map { demoTypeName(of: $0) },
            mimeType: context.urlResponse?.mimeType,
            byteCount: context.data.count
        )
        let data = context.data
        Task { @MainActor [log] in
            log.record(choice, for: url, data: data)
        }
        return decoder
    }
}
