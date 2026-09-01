// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

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
/// - parameter sharesFrames: Whether the players of the same image draw from
/// one set of decoded frames, which is what they do in an app. `false` gives
/// every animation a decoder and a window of its own, which is what a wall of
/// different animations costs.
@MainActor
func loadDemoAnimations(
    _ images: [DemoAnimation],
    options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options(),
    sharesFrames: Bool = true
) async -> DemoAnimationLoad {
    var load = DemoAnimationLoad()
    for (index, image) in images.enumerated() {
        guard let url = image.url else {
            load.status = "There is no \(image.title) image on this platform."
            continue
        }
        do {
            let response = try await ImagePipeline.shared.imageTask(with: url).response
            guard var source = response.container.animation else {
                load.status = "\(image.title) loaded, but it isn't an animated image."
                continue
            }
            // The pool keys the frames it holds on the identity of the source,
            // so every player handed the one the pipeline parsed draws from a
            // single decoder. Parsing the same data again makes an animation
            // the pool has never seen before.
            if !sharesFrames, let copy = await parseDemoAnimation(source.data) {
                source = copy
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

/// Parses the data as an animation off the main thread, which is where a
/// long one belongs: the delays of every frame are read on the way.
private func parseDemoAnimation(_ data: Data) async -> AnimatedImageSource? {
    await Task.detached(priority: .userInitiated) { AnimatedImageSource(data: data) }.value
}

/// One cell per frame: filled when the frame is decoded, and tinted for the
/// frame on screen. A full row means the animation fits in memory, a moving
/// band of filled cells means it doesn't.
struct DemoBufferMap: View {
    let player: AnimatedImagePlayer
    let diagnostics: AnimatedImagePlayer.Diagnostics
    var height: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let count = max(1, diagnostics.frameCount)
            let spacing: CGFloat = count > 60 ? 0.5 : 2
            let width = max(1, (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color(for: index))
                        .frame(width: width)
                }
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            DemoMonoLabel(title)
                .frame(width: 62, alignment: .leading)
            DemoMonoLabel(value, tint: tint ?? .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Views

/// Every animation at once, laid out to fill the space it is given without
/// scrolling.
///
/// What goes over a cell is up to the caller: the frame pool screen puts a
/// badge there, the animation load screen a buffer meter that opens the full
/// diagnostics. The overlay is handed the size of the cell, because a wall of
/// sixty-four has no room for what a wall of four does.
struct DemoAnimationWall<Overlay: View>: View {
    let animations: [DemoLoadedAnimation]
    var spacing: CGFloat = 6
    var cornerRadius: CGFloat = 10
    @ViewBuilder var overlay: (Int, CGSize) -> Overlay

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
                .overlay { overlay(index, size) }
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
struct DemoDiagnosticsPanel: View {
    let player: AnimatedImagePlayer
    let diagnostics: AnimatedImagePlayer.Diagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DemoBufferMap(player: player, diagnostics: diagnostics)
            Divider()
            grid
        }
    }

    private var grid: some View {
        VStack(spacing: 6) {
            DemoDiagnosticsRow("frame", "\(diagnostics.currentFrameIndex + 1)/\(diagnostics.frameCount)  ·  loop \(diagnostics.completedLoopCount)")
            DemoDiagnosticsRow("buffer", "\(demoPad("\(diagnostics.bufferedFrameCount)/\(diagnostics.bufferCapacity)", to: 7)) frames  ·  \(demoPad(demoByteCount(diagnostics.bufferedByteCount), to: 8)) of \(demoByteCount(diagnostics.bufferByteLimit))")
            DemoDiagnosticsRow("decoded", "\(demoPad("\(diagnostics.decodedFrameCount)", to: 5)) frames")
            DemoDiagnosticsRow("decode", "\(demoMilliseconds(diagnostics.lastDecodeDuration)) last  ·  \(demoMilliseconds(diagnostics.averageDecodeDuration)) avg  ·  \(demoMilliseconds(diagnostics.maxDecodeDuration)) max")
            DemoDiagnosticsRow("fps", "\(rate(diagnostics.effectiveFrameRate)) of \(rate(player.source.nominalFrameRate))")
            DemoDiagnosticsRow("shown", "\(diagnostics.displayedFrameCount) frames in \(demoSeconds(diagnostics.playbackTime))")
            DemoDiagnosticsRow(
                "missed",
                "\(diagnostics.skippedFrameCount) behind  ·  \(diagnostics.bufferMissCount) not ready",
                tint: diagnostics.skippedFrameCount > 0 || diagnostics.bufferMissCount > 0 ? .orange : nil
            )
            DemoDiagnosticsRow("size", size, tint: decodedSize == nil ? nil : .accentColor)
            DemoDiagnosticsRow("cost", "\(demoByteCount(bytesPerDecodedFrame))/frame  ·  \(demoByteCount(player.source.data.count)) encoded")
            DemoDiagnosticsRow("length", "\(demoSeconds(player.source.duration))  ·  \(player.source.loopCount == 0 ? "loops forever" : "\(player.source.loopCount) loops")")
            if diagnostics.sharingPlayerCount > 1 {
                DemoDiagnosticsRow("shared", "\(diagnostics.sharingPlayerCount) players on these frames", tint: .accentColor)
            }
        }
    }

    /// The canvas the animation declares, and – when the frames are being
    /// scaled down – the size they are actually decoded at.
    private var size: String {
        let canvas = "\(demoPixels(player.source.size)) px"
        guard let decodedSize else { return canvas }
        return "\(canvas) → \(demoPixels(decodedSize)) px"
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

/// The longest side the frames are decoded at, `nil` being the size they were
/// authored at. ``AnimatedImageView`` derives one from its own bounds; a player
/// built by hand takes what it is given.
let demoMaxPixelSizes: [CGFloat?] = [nil, 120, 240, 480]

func demoPixelSize(_ size: CGFloat?) -> String {
    size.map { "\(Int($0))" } ?? "Full"
}

func demoPixelSizeSubtitle(_ size: CGFloat?) -> String {
    size.map { "\(Int($0)) px" } ?? "as authored"
}

func demoPixels(_ size: CGSize) -> String {
    "\(Int(size.width))×\(Int(size.height))"
}

func demoMilliseconds(_ value: TimeInterval) -> String {
    String(format: "%.1fms", value * 1000)
}

func demoSeconds(_ value: TimeInterval) -> String {
    String(format: "%.1fs", value)
}
