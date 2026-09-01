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
