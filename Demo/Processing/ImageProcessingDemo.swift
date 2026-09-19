// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI
import UIKit

/// Demonstrates the built-in image processors and how to write a custom one,
/// with a thumbnail beside the resize, what each tile cost, and the key its
/// image is cached under.
///
/// ```swift
/// ImageRequest(url: url, processors: [.resize(width: 320), .circle()])
/// ```
///
/// The screen has a pipeline of its own, "Image Processing": a memory cache
/// of its own, so every visit does the work the tiles describe, and
/// diagnostics, which is where the figures under the tiles come from. The
/// shared pipeline records nothing, and an iPad's Getting Started has the
/// same photo in its memory cache from launch.
struct ImageProcessingDemo: View {
    @StateObject private var model = ImageProcessingDemoModel()

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Under each image: the bitmap the decoder made, the image the processors made from it, what that costs in memory, and the key it is cached under. Requests with the same key share an entry.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(model.examples) { example in
                        ProcessingTile(example: example, model: model)
                    }
                }
                .id(model.runID)
            }
            .padding(16)
        }
        .toolbar {
            Button {
                model.runAgain()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Process Again")
        }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Image Processing",
        "Processors run on a background queue and the result goes into the memory cache, so the work is done only once. Requests that differ only in their processors still share a single download, and a single decode of the original.",
        code: """
        ImageRequest(url: url, processors: [
            .resize(width: 320),
            .circle()
        ])

        // Or decode at the size you need
        var request = ImageRequest(url: url)
        request.thumbnail = .init(size: size)
        """,
        points: [
            .init("Built in", "Resize, circle, rounded corners, blur, and any Core Image filter."),
            .init("Cache key", "`pipeline.cache.makeDataCacheKey(for:)` is the key an image is stored under on disk: the image ID – the URL, unless you set one – then the thumbnail's identifier and each processor's `identifier`, in order. The memory cache keys on the same parts and the scale, and compares processors by `hashableIdentifier`. Two requests whose keys match share an entry, whoever made it. Under each tile the URL is cut short, and Nuke's own identifiers lose their `com.github.kean/nuke/` prefix."),
            .init("Thumbnail or resize", "`.resize` decodes the whole image, then draws it smaller: the 1440×960 photo is a 5.3 MB bitmap before it is the few hundred kilobytes under the tile. `request.thumbnail` has Image I/O decode the image at the size asked for, and the full bitmap is never made, which is what an app with a grid of photos wants. The two take about the same time here; the difference is the memory at the peak."),
            .init("Custom", "Conform to `ImageProcessing`. The `identifier` is what the caches key on, so it has to describe the parameters."),
            .init("Anonymous", "`.process(id:_:)` wraps a closure, and the `id` is all the caches know of it: change what the closure does and keep the id, and they serve the old result."),
            .init("Order", "Resize first. Everything after it works on fewer pixels."),
            .init("Caching", "A request with processors stores only the processed image in the memory cache, not the original it was made from. Here the Original tile keeps the original there, so a tile that loads after it reads \"original from memory\" and does only the processing."),
            .init("The figures", "They come from each task's `ImageTask.Metrics`: this screen's pipeline records them. The bitmap sizes assume 4 bytes a pixel; the cost of the result is what the memory cache charges for it. A tile served from the memory cache has no task, and keeps the figures of the run that made its image. The button in the toolbar empties the memory cache and processes every tile again.")
        ]
    )
}

/// One example: its image, the work behind it, and its key.
private struct ProcessingTile: View {
    let example: ImageProcessingDemoModel.Example
    @ObservedObject var model: ImageProcessingDemoModel

    var body: some View {
        DemoExample(example.title, caption: example.caption) {
            LazyImage(request: example.request) { state in
                if let image = state.image {
                    image.resizable().scaledToFit()
                } else if state.error != nil {
                    DemoFailureView()
                } else {
                    DemoPlaceholder()
                }
            }
            .pipeline(model.pipeline)
            .onStart { model.didStart(example, task: $0) }
            .onCompletion { model.didComplete(example, result: $0) }
            .frame(height: 110)

            VStack(alignment: .leading, spacing: 1) {
                let figures = model.figures[example.id]
                DemoMonoLabel(figures?.decoded ?? " ", tint: figures?.isFailure == true ? .red : nil)
                DemoMonoLabel(figures?.result ?? " ")
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Text(model.keys[example.id] ?? "")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
private final class ImageProcessingDemoModel: ObservableObject {
    struct Example: Identifiable {
        let id: String
        let caption: String
        let request: ImageRequest

        var title: String { id }
    }

    /// What one tile's last run did.
    struct Figures {
        /// "decoded 1440×960 · 5.3 MB", or "original from memory".
        let decoded: String
        /// "495×330 · 653 KB · 12.1ms": the image, its memory cost, and the
        /// time the decoding, processing, and decompression took.
        let result: String
        var isFailure = false
    }

    let pipeline: ImagePipeline
    let examples: [Example]

    @Published private(set) var figures: [Example.ID: Figures] = [:]
    @Published private(set) var runID = UUID()

    /// Each example's disk cache key, readable: see ``readableKey(for:)``.
    let keys: [Example.ID: String]

    private var tasks: [Example.ID: ImageTask] = [:]

    init() {
        var configuration = ImagePipeline.Configuration.withURLCache
        configuration.imageCache = ImageCache()
        configuration.isDiagnosticsEnabled = true
        let pipeline = DemoPipelineProbe.makePipeline("Image Processing", configuration: configuration)
        self.pipeline = pipeline
        let examples = Self.makeExamples(url: DemoImages.landscape)
        self.examples = examples
        self.keys = Dictionary(uniqueKeysWithValues: examples.map {
            ($0.id, Self.readableKey(for: $0.request, pipeline: pipeline))
        })
    }

    func didStart(_ example: Example, task: ImageTask) {
        tasks[example.id] = task
    }

    func didComplete(_ example: Example, result: Result<ImageResponse, ImagePipeline.Error>) {
        // A memory cache hit has no task, and leaves the figures of the run
        // that put the image there.
        guard let task = tasks.removeValue(forKey: example.id) else { return }
        switch result {
        case .success:
            if let metrics = task.metrics, let figures = Self.figures(of: metrics) {
                self.figures[example.id] = figures
            }
        case .failure(.cancelled):
            break
        case .failure(let error):
            figures[example.id] = Figures(decoded: "failed · \(error.demoSummary)", result: " ", isFailure: true)
        }
    }

    /// Processes every tile again: the memory cache is emptied and the tiles
    /// are made anew. The downloads come from `URLCache`.
    func runAgain() {
        pipeline.cache.removeAll(caches: [.memory])
        tasks.removeAll()
        figures.removeAll()
        runID = UUID()
    }

    // MARK: Reading the Record

    private static func figures(of metrics: ImageTask.Metrics) -> Figures? {
        guard let image = metrics.image else { return nil }
        let stages = metrics.jobs.flatMap(\.stages).filter { $0.isProgressive != true }
        let workKinds: [ImagePipeline.Diagnostics.Stage.Kind] = [.decode, .process, .decompress]
        let work = stages
            .filter { workKinds.contains($0.kind) }
            .reduce(0) { $0 + ($1.workDuration ?? $1.duration ?? 0) }

        let decoded: String
        if let pixels = stages.last(where: { $0.kind == .decode })?.pixels {
            decoded = "decoded \(pixels.width)×\(pixels.height) · \(demoByteCount(pixels.width * pixels.height * 4))"
        } else if stages.contains(where: { $0.kind == .process }) {
            // A processed image made from the original another tile left in
            // the memory cache: nothing to decode.
            decoded = "original from memory"
        } else {
            decoded = "not decoded"
        }
        let cost = image.memoryCost.map(demoByteCount) ?? "–"
        return Figures(
            decoded: decoded,
            result: "\(image.width)×\(image.height) · \(cost) · \(demoMilliseconds(work))"
        )
    }

    // MARK: Keys

    /// The disk cache key of a request, a part a line: the image ID with the
    /// URL cut short, then the thumbnail's identifier and each processor's,
    /// less Nuke's namespace. The parts are cut out of the key itself, so a
    /// key made some other way – by a delegate, say – is shown whole.
    private static func readableKey(for request: ImageRequest, pipeline: ImagePipeline) -> String {
        let key = pipeline.cache.makeDataCacheKey(for: request)
        let processors = request.processors.map(\.identifier)
        guard let imageID = request.imageID, key.hasPrefix(imageID),
              key.hasSuffix(processors.joined()) else {
            return key
        }
        // What is left between the two is the thumbnail's identifier, which
        // isn't public on its own.
        let thumbnail = String(key.dropFirst(imageID.count).dropLast(processors.joined().count))
        let identifiers = ([thumbnail] + processors).filter { !$0.isEmpty }
        return ([shortName(of: imageID)] + identifiers.map { "+ " + wrappable(withoutNamespace($0)) })
            .joined(separator: "\n")
    }

    /// Lets a long identifier wrap after its punctuation rather than in the
    /// middle of a word: a zero-width space after each `?` and `,`, and after
    /// a `.` that isn't in a number. The text isn't a key to copy anyway.
    private static func wrappable(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: ",", with: ",\u{200B}")
            .replacingOccurrences(of: "?", with: "?\u{200B}")
            .replacingOccurrences(of: #"\.(?=[A-Za-z])"#, with: ".\u{200B}", options: .regularExpression)
    }

    /// `59150453….jpeg`: the file name is enough to tell which URL it is.
    private static func shortName(of imageID: String) -> String {
        guard let url = URL(string: imageID) else { return imageID }
        let stem = url.deletingPathExtension().lastPathComponent
        let name = stem.count > 12 ? "\(stem.prefix(8))…" : stem
        return url.pathExtension.isEmpty ? name : "\(name).\(url.pathExtension)"
    }

    private static func withoutNamespace(_ identifier: String) -> String {
        // The thumbnail's namespace is spelled differently from the
        // processors'.
        for namespace in ["com.github.kean/nuke/", "com.github/kean/nuke/"] where identifier.hasPrefix(namespace) {
            return String(identifier.dropFirst(namespace.count))
        }
        return identifier
    }

    // MARK: Examples

    private static let size = CGSize(width: 160, height: 110)

    private static func makeExamples(url: URL) -> [Example] {
        func example(_ title: String, _ caption: String, _ processors: [any ImageProcessing]) -> Example {
            Example(id: title, caption: caption, request: ImageRequest(url: url, processors: processors))
        }
        var thumbnail = ImageRequest(url: url)
        thumbnail.thumbnail = ImageRequest.ThumbnailOptions(size: size)
        return [
            example("Original", "No processors", []),
            example("Resize", ".resize(size:)", [
                .resize(size: size)
            ]),
            Example(id: "Thumbnail", caption: "request.thumbnail, the same size", request: thumbnail),
            example("Crop", ".resize(size:crop:)", [
                .resize(size: size, contentMode: .aspectFill, crop: true)
            ]),
            example("Rounded Corners", ".roundedCorners(radius:)", [
                .resize(size: size, crop: true),
                .roundedCorners(radius: 16)
            ]),
            example("Circle", ".circle(border:)", [
                .resize(size: CGSize(width: 110, height: 110), crop: true),
                .circle(border: .init(color: .systemBlue, width: 2))
            ]),
            example("Blur", ".gaussianBlur(radius:)", [
                .resize(size: size, crop: true),
                .gaussianBlur(radius: 8)
            ]),
            example("Core Image", ".coreImageFilter(name:)", [
                .resize(size: size, crop: true),
                .coreImageFilter(name: "CISepiaTone")
            ]),
            example("Custom", "A custom ImageProcessing type", [
                .resize(size: size, crop: true),
                GrayscaleProcessor()
            ]),
            example("Anonymous", ".process(id:_:)", [
                .resize(size: size, crop: true),
                .process(id: "com.github.kean.demo.tint") { image in
                    // At the image's own scale: the renderer's default is the
                    // screen's, which would draw the image three times over
                    // on an iPhone.
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = image.scale
                    return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
                        image.draw(at: .zero)
                        UIColor(red: 0, green: 0.48, blue: 1, alpha: 0.35).setFill()
                        // `fill(_:)` alone copies the color over the image,
                        // alpha and all, and leaves a pale blue rectangle.
                        context.fill(CGRect(origin: .zero, size: image.size), blendMode: .normal)
                    }
                }
            ])
        ]
    }
}

/// A custom processor. Implementing ``ImageProcessing`` takes two things: the
/// processing itself, and an identifier that makes the processed image
/// distinct from the original one in the cache.
///
/// Conforming to `Hashable` also gives you a `hashableIdentifier` used by the
/// memory cache, where string comparisons would be too slow.
private struct GrayscaleProcessor: ImageProcessing, Hashable {
    let identifier = "com.github.kean.demo.grayscale"

    func process(_ image: PlatformImage) -> PlatformImage? {
        guard let cgImage = image.cgImage else { return nil }
        guard let context = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard let output = context.makeImage() else { return nil }
        return UIImage(cgImage: output, scale: image.scale, orientation: image.imageOrientation)
    }
}
