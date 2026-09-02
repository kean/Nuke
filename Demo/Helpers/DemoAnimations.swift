// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import ImageIO
import NukeUI
import SwiftUI

/// The animated images the demo plays, and the pieces both animation screens
/// are built from.
enum DemoAnimation: String, CaseIterable, Identifiable {
    case gif, apng, webp, heic, large

    var id: String { rawValue }

    /// The ones there is actually an image for on this platform.
    static var available: [DemoAnimation] {
        allCases.filter { $0.url != nil }
    }

    var title: String {
        switch self {
        case .gif: "GIF"
        case .apng: "APNG"
        case .webp: "WebP"
        case .heic: "HEIC"
        case .large: "Large"
        }
    }

    var url: URL? {
        switch self {
        case .gif: DemoImages.gif
        case .apng: DemoImages.apng
        case .webp: DemoImages.animatedWebP
        case .heic: DemoImages.animatedHEIC
        case .large: DemoImages.largeGIF
        }
    }
}

/// One animation on screen: the player that drives it, and the still the
/// decoder produced to hold its place until the first frame lands.
struct DemoLoadedAnimation: Identifiable {
    let id: Int
    let title: String
    let player: AnimatedImagePlayer
    let poster: UIImage?
}

/// What the animations picked came back as, or why they didn't.
struct DemoAnimationLoad {
    var animations: [DemoLoadedAnimation] = []
    var status: String?
}

/// Loads the given animations and builds a player for each one, playing.
///
/// `LazyImage` does all of this on its own; the animation screens build the
/// players by hand to get at ``AnimatedImagePlayer/diagnostics``.
@MainActor
func loadDemoAnimations(
    _ images: [DemoAnimation],
    options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options()
) async -> DemoAnimationLoad {
    var load = DemoAnimationLoad()
    for (index, image) in images.enumerated() {
        guard let url = image.url else {
            load.status = "There is no \(image.title) image on this platform."
            continue
        }
        do {
            let response = try await ImagePipeline.shared.imageTask(with: url).response
            guard let source = response.container.animation else {
                load.status = "\(image.title) loaded, but it isn't an animated image."
                continue
            }
            var options = options
            // `AnimatedImageView` does this for the players it makes; a player
            // built by hand has to be told, or the animation changes size the
            // moment it takes over from the still.
            options.scale = response.image.scale
            let player = AnimatedImagePlayer(source: source, options: options)
            player.play()
            load.animations.append(DemoLoadedAnimation(
                id: index,
                title: image.title,
                player: player,
                poster: response.image
            ))
        } catch {
            load.status = "Failed to load: \(error.localizedDescription)"
        }
    }
    return load
}

/// One cell per frame: filled when the frame is decoded, and tinted for the
/// frame on screen. A full row means the animation fits in memory, a moving
/// band of filled cells means it doesn't.
///
/// Given ``onScrub``, the map is also the scrubber: the cells are the timeline
/// and the tinted one is the thumb, so a slider beside it would be the same
/// thing drawn twice.
struct DemoBufferMap: View {
    let player: AnimatedImagePlayer
    let diagnostics: AnimatedImagePlayer.Diagnostics
    var height: CGFloat = 24
    /// Called with the frame under the finger as it drags across the map.
    /// `nil` – the default – for a map that only shows.
    var onScrub: ((Int) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let count = max(1, diagnostics.frameCount)
            let spacing: CGFloat = count > 60 ? 0.5 : 2
            let width = max(1, (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            let cells = HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color(for: index))
                        .frame(width: width)
                }
            }
            if let onScrub {
                cells
                    // The gaps between the cells are part of the timeline.
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        let index = Int(value.location.x / proxy.size.width * CGFloat(count))
                        onScrub(min(max(0, index), count - 1))
                    })
            } else {
                cells
            }
        }
        .frame(height: height)
    }

    private func color(for index: Int) -> Color {
        if index == diagnostics.currentFrameIndex {
            return .accentColor
        }
        return player.isFrameBuffered(index) ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.07)
    }
}

/// The frames a buffer is holding, padded to the width the figure reaches when
/// the buffer is full, so that it doesn't move as it fills.
func demoFrameCount(_ diagnostics: AnimatedImagePlayer.Diagnostics) -> String {
    let total = "\(diagnostics.frameCount)"
    return demoPad("\(diagnostics.bufferedFrameCount)/\(total)", to: total.count * 2 + 1)
}

/// One labelled line of the diagnostics.
///
/// One line whatever the value: a row that wrapped when a figure grew would
/// move every row under it, so a value the column can't fit shrinks instead.
struct DemoDiagnosticsRow: View {
    private let title: String
    private let value: String
    /// Orange for the frames playback couldn't keep up with, the accent color
    /// for a setting that is visibly doing something.
    private let tint: Color?

    init(_ title: String, _ value: String, tint: Color? = nil) {
        self.title = title
        self.value = value
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            DemoMonoLabel(title)
                .frame(width: 62, alignment: .leading)
            DemoMonoLabel(value, tint: tint ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Views

/// Every animation at once, laid out to fill the space it is given without
/// scrolling.
///
/// What goes over a cell is up to the caller: the frame pool screen puts a
/// badge there with what the cell is holding.
struct DemoAnimationWall<Overlay: View>: View {
    let animations: [DemoLoadedAnimation]
    var spacing: CGFloat = 6
    var cornerRadius: CGFloat = 10
    @ViewBuilder var overlay: (Int) -> Overlay

    var body: some View {
        GeometryReader { proxy in
            let grid = demoWallGrid(count: animations.count)
            let size = demoWallCellSize(count: animations.count, in: proxy.size, spacing: spacing)
            VStack(spacing: spacing) {
                ForEach(0..<grid.rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<grid.columns, id: \.self) { column in
                            cell(at: row * grid.columns + column, size: size)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(at index: Int, size: CGSize) -> some View {
        if index < animations.count {
            let animation = animations[index]
            AnimatedImage(player: animation.player, poster: animation.poster)
                .resizable()
                .scaledToFill()
                // Before the overlay and the corners: filling means the frames
                // are larger than the cell, and what hangs over the edge is
                // the cell's to trim.
                .frame(width: size.width, height: size.height)
                .clipped()
                .overlay { overlay(index) }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            Color.clear.frame(width: size.width, height: size.height)
        }
    }
}

/// The grid a wall of animations is laid out on: as many columns as the square
/// root of the count, which keeps the cells as square and as large as the space
/// allows.
func demoWallGrid(count: Int) -> (columns: Int, rows: Int) {
    let columns = max(1, Int(Double(count).squareRoot().rounded(.up)))
    let rows = max(1, Int((Double(count) / Double(columns)).rounded(.up)))
    return (columns, rows)
}

/// The size of one cell of that grid, which is also the size the frames of the
/// animation in it are worth decoding at.
func demoWallCellSize(count: Int, in size: CGSize, spacing: CGFloat = 6) -> CGSize {
    let grid = demoWallGrid(count: count)
    return CGSize(
        width: max(1, (size.width - spacing * CGFloat(grid.columns - 1)) / CGFloat(grid.columns)),
        height: max(1, (size.height - spacing * CGFloat(grid.rows - 1)) / CGFloat(grid.rows))
    )
}

/// The numbers behind one animation: the buffer map, and everything
/// ``AnimatedImagePlayer/diagnostics`` reports about the player under it.
///
/// What the container declares – the delays, the loop count, the pixel format
/// – is ``DemoAnimationDetails``, which the animation screen folds away under
/// this.
struct DemoDiagnosticsPanel: View {
    let player: AnimatedImagePlayer
    let diagnostics: AnimatedImagePlayer.Diagnostics
    /// The size the animation is drawn at, in points, for a line on how the
    /// frames compare with the pixels they cover. `nil` – the default – for no
    /// such line.
    var drawnSize: CGSize?
    /// The playback controls that sit right under the scrubber, where a
    /// player keeps them. `nil` – the default – for none.
    var transport: AnyView?
    /// What the shared pool holds across every animation, for a closing line
    /// that puts this player's cost against the ceiling it plays under. `nil`
    /// – the default – for no such line.
    var pool: DemoPoolDiagnostics?

    /// Makes the buffer map the scrubber – see ``DemoBufferMap/onScrub``.
    var onScrub: ((Int) -> Void)?

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DemoBufferMap(player: player, diagnostics: diagnostics, onScrub: onScrub)
            if let transport {
                transport
            }
            Divider()
            grid
        }
    }

    /// The figures in clusters – playback, the decoder, the clock, the
    /// pixels and their cost, closing on the pool they all share – a breath
    /// between clusters and a tight line
    /// within, so the rows read as four things rather than a wall. Each line
    /// is short enough for the column, and the figures that swing are padded
    /// so that the words after them stay put.
    private var grid: some View {
        let frameCount = diagnostics.frameCount
        let frame = demoPad("\(diagnostics.currentFrameIndex + 1)", to: "\(frameCount)".count)
        let buffered = demoPad("\(diagnostics.bufferedFrameCount)", to: "\(diagnostics.bufferCapacity)".count)
        return VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 4) {
                DemoDiagnosticsRow("frame", "\(frame)/\(frameCount) · \(demoDelay(currentDelay)) · loop \(diagnostics.completedLoopCount)")
                DemoDiagnosticsRow("buffer", "\(buffered)/\(diagnostics.bufferCapacity) · \(demoPad(demoByteCount(diagnostics.bufferedByteCount), to: 7)) of \(demoByteCount(diagnostics.bufferByteLimit))")
            }
            VStack(spacing: 4) {
                DemoDiagnosticsRow("decoded", "\(diagnostics.decodedFrameCount) frames · \(demoDuration(totalDecodeDuration)) decoding")
                DemoDiagnosticsRow("decode", "\(demoMilliseconds(diagnostics.lastDecodeDuration)) · \(demoMilliseconds(diagnostics.averageDecodeDuration)) avg · \(demoMilliseconds(diagnostics.maxDecodeDuration)) max")
            }
            VStack(spacing: 4) {
                DemoDiagnosticsRow("fps", "\(rate(diagnostics.effectiveFrameRate)) of \(rate(player.source.nominalFrameRate)) · \(frameRatePercent)%")
                DemoDiagnosticsRow("shown", "\(diagnostics.displayedFrameCount) frames in \(demoSeconds(diagnostics.playbackTime))")
                DemoDiagnosticsRow(
                    "late",
                    "\(diagnostics.bufferMissCount) frames not ready in time",
                    tint: diagnostics.bufferMissCount > 0 ? .orange : nil
                )
            }
            VStack(spacing: 4) {
                DemoDiagnosticsRow("size", size, tint: decodedSize == nil ? nil : .accentColor)
                if let screen {
                    DemoDiagnosticsRow("screen", screen.text, tint: screen.tint)
                }
                DemoDiagnosticsRow("cost", "\(demoByteCount(bytesPerDecodedFrame)) × \(frameCount) = \(demoByteCount(bytesPerDecodedFrame * frameCount))")
                if diagnostics.sharingPlayerCount > 1 {
                    DemoDiagnosticsRow("shared", "\(diagnostics.sharingPlayerCount) players on these frames", tint: .accentColor)
                }
                if let pool {
                    DemoDiagnosticsRow("pool", "\(demoPad(demoByteCount(pool.totalCost), to: 7)) of \(demoByteCount(pool.costLimit)) · \(pool.animationCount) animation\(pool.animationCount == 1 ? "" : "s")")
                }
            }
        }
    }

    /// How long the frame on screen is shown for.
    private var currentDelay: TimeInterval {
        let delays = player.source.delays
        return delays.indices.contains(diagnostics.currentFrameIndex) ? delays[diagnostics.currentFrameIndex] : 0
    }

    /// The time the decoder has spent on this player's frames.
    private var totalDecodeDuration: TimeInterval {
        diagnostics.averageDecodeDuration * Double(diagnostics.decodedFrameCount)
    }

    /// The frame rate as a share of the one the animation asks for. Below a
    /// hundred means the animation is being stretched.
    private var frameRatePercent: Int {
        let nominal = player.source.nominalFrameRate
        guard nominal > 0 else { return 0 }
        return min(999, Int((diagnostics.effectiveFrameRate / nominal * 100).rounded()))
    }

    /// The canvas the animation declares, and – when the frames are being
    /// scaled down – the size they are actually decoded at, with the scale.
    private var size: String {
        let canvas = demoPixels(player.source.size)
        guard let decodedSize else { return "\(canvas) px" }
        let scale = decodedSize.width / max(1, player.source.size.width)
        return "\(canvas) → \(demoPixels(decodedSize)) px · \(Int((scale * 100).rounded()))%"
    }

    /// The pixels the animation covers on screen, and how the frames on it
    /// compare: stretched when they are decoded smaller than that, shrunk when
    /// larger, and neither when they are drawn pixel for pixel.
    private var screen: (text: String, tint: Color?)? {
        guard let drawnSize, drawnSize.width > 0, drawnSize.height > 0 else { return nil }
        let pixels = CGSize(width: drawnSize.width * displayScale, height: drawnSize.height * displayScale)
        let drawn = "\(demoPixels(pixels)) px"
        guard let image = player.image?.cgImage else { return (drawn, nil) }
        let ratio = max(pixels.width, pixels.height) / CGFloat(max(image.width, image.height))
        if ratio > 1.05 {
            return ("\(drawn) · frames stretched \(String(format: "%.1f", ratio))×", .orange)
        }
        if ratio < 0.95 {
            return ("\(drawn) · frames shrunk to \(Int((ratio * 100).rounded()))%", nil)
        }
        return ("\(drawn) · pixel for pixel", .accentColor)
    }

    /// The size of the frames on screen, when it isn't the canvas size.
    ///
    /// Read off the frame the player is showing rather than computed from
    /// ``AnimatedImagePlayer/Options/maxPixelSize``, so it is what the decoder
    /// produced and not what it was asked for.
    private var decodedSize: CGSize? {
        guard let image = player.image?.cgImage else { return nil }
        let size = CGSize(width: image.width, height: image.height)
        return size == player.source.size ? nil : size
    }

    /// What one frame costs in memory. Measured off the buffer when it holds
    /// anything, because the bitmaps are padded to a row width the compositor
    /// likes and the canvas arithmetic doesn't know about that.
    private var bytesPerDecodedFrame: Int {
        guard diagnostics.bufferedFrameCount > 0 else {
            return player.source.bytesPerFrame
        }
        return diagnostics.bufferedByteCount / diagnostics.bufferedFrameCount
    }

    private func rate(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

/// What the container declares about an animation, read the way
/// `AnimatedImageSource` reads it but kept as declared, corrections and all.
///
/// The source keeps only what playback needs; this is the rest of what parsing
/// turned up, for the details under the diagnostics.
struct DemoAnimationInfo: Sendable {
    /// The uniform type identifier Image I/O recognized the data as.
    var typeIdentifier: String?
    /// The delay of every frame as the file declares it, in seconds – `0`
    /// where it declares none – before the corrections
    /// ``AnimatedImageSource/delays`` applies.
    var declaredDelays: [TimeInterval] = []
    /// Whether the container declares a loop count at all. A GIF without one
    /// plays once, which is a browser rule rather than anything in the file.
    var declaresLoopCount = false
    /// The color model, depth, and alpha the frames are stored with, as Image
    /// I/O describes the first one: "RGB · 8-bit · alpha".
    var storedPixelFormat: String?
    /// The name of the color profile embedded in the file, if there is one.
    var colorProfile: String?

    /// The format by the name people use for it, or the last component of the
    /// type identifier for one without a household name.
    var formatName: String? {
        guard let typeIdentifier else { return nil }
        switch AssetType(rawValue: typeIdentifier) {
        case .gif: return "GIF"
        case .png: return "APNG"
        case .webp: return "WebP"
        case .heic, "public.heics": return "HEIC"
        case .avif, "public.avis": return "AVIF"
        default: return typeIdentifier.split(separator: ".").last.map { String($0).uppercased() }
        }
    }

    /// The number of frames whose declared delay the player replaced with
    /// ``AnimatedImageSource/defaultDelay``: the ones under
    /// ``AnimatedImageSource/minimumDelay``, which old authoring tools wrote to
    /// mean "as fast as possible".
    var clampedFrameCount: Int {
        declaredDelays.filter { $0 < AnimatedImageSource.minimumDelay }.count
    }

    /// Parses the container off the main thread, which is where a scan of a
    /// long GIF belongs.
    static func parse(_ source: AnimatedImageSource) async -> DemoAnimationInfo {
        await Task.detached(priority: .userInitiated) { DemoAnimationInfo(source: source) }.value
    }

    private init(source: AnimatedImageSource) {
        guard let imageSource = source.makeImageSource() else { return }
        typeIdentifier = CGImageSourceGetType(imageSource) as String?
        // Image I/O files the animation metadata under a dictionary named for
        // the format; the keys inside are the same for every one.
        let containerKeys: [CFString] = [
            kCGImagePropertyGIFDictionary,
            kCGImagePropertyPNGDictionary,
            kCGImagePropertyWebPDictionary,
            kCGImagePropertyHEICSDictionary,
            kCGImagePropertyAVISDictionary
        ]
        func container(in properties: [CFString: Any]) -> [CFString: Any]? {
            for key in containerKeys {
                if let container = properties[key] as? [CFString: Any] {
                    return container
                }
            }
            return nil
        }
        if let properties = CGImageSourceCopyProperties(imageSource, nil) as? [CFString: Any] {
            declaresLoopCount = container(in: properties)?["LoopCount" as CFString] != nil
        }
        var delays: [TimeInterval] = []
        for index in 0..<source.frameCount {
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any] ?? [:]
            if index == 0 {
                storedPixelFormat = Self.pixelFormat(properties)
                colorProfile = properties[kCGImagePropertyProfileName] as? String
            }
            // The unclamped value is the one the file asks for; the other has
            // already been raised to 100 ms by Image I/O.
            let container = container(in: properties)
            delays.append((container?["UnclampedDelayTime" as CFString] as? TimeInterval)
                ?? (container?["DelayTime" as CFString] as? TimeInterval)
                ?? 0)
        }
        declaredDelays = delays
    }

    private static func pixelFormat(_ properties: [CFString: Any]) -> String? {
        guard let model = properties[kCGImagePropertyColorModel] as? String else { return nil }
        var parts = [model]
        if let depth = properties[kCGImagePropertyDepth] as? Int {
            parts.append("\(depth)-bit")
        }
        parts.append(properties[kCGImagePropertyHasAlpha] as? Bool == true ? "alpha" : "opaque")
        return parts.joined(separator: " · ")
    }
}

/// What the container declares about the animation, against what the player
/// made of it: the format, the delays and how many the browser rule
/// corrected, the loop count, and the pixel format the frames are stored in
/// beside the one they are decoded into.
struct DemoAnimationDetails: View {
    let player: AnimatedImagePlayer
    let diagnostics: AnimatedImagePlayer.Diagnostics
    /// `nil` while the container is still being parsed.
    let info: DemoAnimationInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if delaysVary {
                DemoDelayMap(delays: source.delays, currentFrameIndex: diagnostics.currentFrameIndex)
                Divider()
            }
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 4) {
                    DemoDiagnosticsRow("format", format)
                    DemoDiagnosticsRow("canvas", "\(demoPixels(source.size)) px · \(demoByteCount(source.bytesPerFrame))/frame")
                    DemoDiagnosticsRow("frames", "\(source.frameCount) · \(demoSeconds(source.duration)) per loop · \(String(format: "%.1f", source.nominalFrameRate)) fps")
                }
                VStack(spacing: 4) {
                    DemoDiagnosticsRow("delay", delay)
                    if let info, info.clampedFrameCount > 0 {
                        DemoDiagnosticsRow(
                            "clamped",
                            "\(info.clampedFrameCount) frames under \(demoDelay(AnimatedImageSource.minimumDelay)) → \(demoDelay(AnimatedImageSource.defaultDelay))",
                            tint: .orange
                        )
                    }
                    DemoDiagnosticsRow("loops", loops)
                }
                VStack(spacing: 4) {
                    DemoDiagnosticsRow("encoded", "\(demoByteCount(source.data.count)) · \(demoByteCount(source.data.count / source.frameCount))/frame")
                    DemoDiagnosticsRow("stored", info.map { $0.storedPixelFormat ?? "unknown" } ?? "parsing…")
                    if let profile = info?.colorProfile {
                        DemoDiagnosticsRow("profile", profile)
                    }
                    DemoDiagnosticsRow("bitmap", bitmap)
                }
            }
        }
    }

    private var source: AnimatedImageSource {
        player.source
    }

    private var format: String {
        guard let info else { return "parsing…" }
        guard let identifier = info.typeIdentifier else { return "unrecognized" }
        return "\(info.formatName ?? identifier) · \(identifier)"
    }

    /// The delays as they are played, in whole milliseconds.
    private var delaysInMilliseconds: [Int] {
        source.delays.map { Int(($0 * 1000).rounded()) }
    }

    private var delaysVary: Bool {
        Set(delaysInMilliseconds).count > 1
    }

    /// One delay when every frame has it; the range and the most common one
    /// when they differ.
    private var delay: String {
        let delays = delaysInMilliseconds
        guard let shortest = delays.min(), let longest = delays.max() else { return "–" }
        guard delaysVary else { return "\(shortest)ms · every frame" }
        let counts = Dictionary(delays.map { ($0, 1) }, uniquingKeysWith: +)
        let mode = counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? shortest
        return "\(shortest)–\(longest)ms · mostly \(mode)ms"
    }

    private var loops: String {
        let count = switch source.loopCount {
        case 0: "forever"
        case 1: "once"
        default: "\(source.loopCount) times"
        }
        return info?.declaresLoopCount == false ? "\(count) · none declared" : count
    }

    /// The bitmap the frames are decoded into, read off the one on screen.
    private var bitmap: String {
        guard let image = player.image?.cgImage else { return "decoding…" }
        // Eight bits a channel goes without saying; anything else doesn't.
        let depth = image.bitsPerComponent == 8 ? "" : " \(image.bitsPerComponent)-bit"
        return "\(channels(of: image))\(depth) · \(alpha(of: image)) · \(colorSpace(of: image))"
    }

    /// The order of the channels in memory, which is what the byte order and
    /// the alpha position add up to.
    private func channels(of image: CGImage) -> String {
        let alphaFirst: Bool
        switch image.alphaInfo {
        case .premultipliedFirst, .first, .noneSkipFirst: alphaFirst = true
        case .premultipliedLast, .last, .noneSkipLast: alphaFirst = false
        default: return "RGB"
        }
        let isLittleEndian = image.bitmapInfo.contains(.byteOrder32Little)
        switch (isLittleEndian, alphaFirst) {
        case (true, true): return "BGRA"
        case (true, false): return "ABGR"
        case (false, true): return "ARGB"
        case (false, false): return "RGBA"
        }
    }

    private func alpha(of image: CGImage) -> String {
        switch image.alphaInfo {
        case .premultipliedFirst, .premultipliedLast: "premultiplied"
        case .first, .last: "alpha"
        default: "opaque"
        }
    }

    private func colorSpace(of image: CGImage) -> String {
        guard let name = image.colorSpace?.name as String? else {
            return "ICC profile"
        }
        return switch name.replacingOccurrences(of: "kCGColorSpace", with: "") {
        case "SRGB": "sRGB"
        case "ExtendedSRGB": "extended sRGB"
        case "LinearSRGB": "linear sRGB"
        case "DisplayP3": "Display P3"
        case "DeviceRGB": "device RGB"
        case "GenericRGB": "generic RGB"
        case let other: other
        }
    }
}

/// One bar per frame, as tall as the frame is long, with the frame on screen
/// tinted: the rhythm of the animation. Only worth drawing when the delays
/// differ – equal ones are the buffer map over again.
struct DemoDelayMap: View {
    let delays: [TimeInterval]
    let currentFrameIndex: Int
    var height: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let count = max(1, delays.count)
            let spacing: CGFloat = count > 60 ? 0.5 : 2
            let width = max(1, (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            let longest = max(delays.max() ?? 0, 0.001)
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(delays.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(index == currentFrameIndex ? Color.accentColor : Color.accentColor.opacity(0.3))
                        .frame(width: width, height: max(2, height * delays[index] / longest))
                }
            }
            .frame(height: height, alignment: .bottom)
        }
        .frame(height: height)
    }
}

/// What the shared pool is doing, sampled on the same timer as the players.
struct DemoPoolDiagnostics {
    var costLimit = 0
    var totalCost = 0
    var playerCount = 0
    var activePlayerCount = 0
    var animationCount = 0

    var fraction: Double {
        costLimit > 0 ? min(1, Double(totalCost) / Double(costLimit)) : 0
    }

    /// How many players there are for every set of decoded frames.
    var sharing: Double {
        animationCount > 0 ? Double(playerCount) / Double(animationCount) : 0
    }

    init() {}

    @MainActor
    init(pool: AnimatedImageFramePool) {
        costLimit = pool.costLimit
        totalCost = pool.totalCost
        playerCount = pool.playerCount
        activePlayerCount = pool.activePlayerCount
        animationCount = pool.animationCount
    }
}

/// What the pool is holding against what it is allowed to hold.
struct DemoPoolMeter: View {
    let pool: DemoPoolDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(pool.fraction > 0.95 ? Color.orange : Color.accentColor)
                        .frame(width: proxy.size.width * pool.fraction)
                }
            }
            .frame(height: 10)
            DemoDiagnosticsRow("pool", "\(demoPad(demoByteCount(pool.totalCost), to: 8)) of \(demoByteCount(pool.costLimit))")
            DemoDiagnosticsRow("players", "\(pool.playerCount) sharing  ·  \(pool.activePlayerCount) filling")
            // The players outnumber the animations as soon as one of them is on
            // screen twice.
            DemoDiagnosticsRow("frames", "\(pool.animationCount) sets for \(pool.playerCount) players"
                + (pool.sharing > 1 ? String(format: "  ·  ×%.1f", pool.sharing) : ""))
        }
    }
}

// MARK: - Formatting

func demoPixels(_ size: CGSize) -> String {
    "\(Int(size.width))×\(Int(size.height))"
}

func demoMilliseconds(_ value: TimeInterval) -> String {
    String(format: "%.1fms", value * 1000)
}

/// A frame delay: whole milliseconds, which is the resolution the containers
/// store them at.
func demoDelay(_ value: TimeInterval) -> String {
    String(format: "%.0fms", value * 1000)
}

func demoSeconds(_ value: TimeInterval) -> String {
    String(format: "%.1fs", value)
}

/// A span that starts in milliseconds and may run into seconds.
func demoDuration(_ value: TimeInterval) -> String {
    value < 1 ? demoDelay(value) : demoSeconds(value)
}
