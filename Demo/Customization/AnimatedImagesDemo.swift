// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI

/// Plays animated images with a live diagnostics overlay: what the frame buffer
/// is holding, what each frame costs to decode, and whether playback is keeping
/// up with the wall clock.
///
/// ```swift
/// LazyImage(url: url) // Plays animated images on its own
/// ```
///
/// This screen does it the long way – it creates the ``AnimatedImagePlayer``
/// itself – because that is what gives it access to
/// ``AnimatedImagePlayer/diagnostics``.
struct AnimatedImagesDemo: View {
    @State private var image: DemoAnimation = .gif
    @State private var settings = DemoAnimationSettings()
    @State private var player: AnimatedImagePlayer?
    @State private var diagnostics = AnimatedImagePlayer.Diagnostics()
    @State private var status: String?
    @State private var isShowingDiagnostics = true

    /// Sampling the player rather than observing it: the diagnostics change on
    /// every frame, and a view that redrew that often would be measuring itself.
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                picker
                stage
                if isShowingDiagnostics, let player {
                    AnimatedImageDiagnosticsView(player: player, diagnostics: diagnostics)
                        .padding(.horizontal, 16)
                }
                transport
                settingsSection
            }
            .padding(.vertical, 16)
        }
        .task(id: reloadID) { await load() }
        .onReceive(timer) { _ in
            guard let player else { return }
            diagnostics = player.diagnostics
        }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Animated Images",
        "NukeUI decodes the frames of an animated image off the main thread and keeps a bounded number of them in memory. Change the buffer and watch the overlay: when the whole animation fits, every frame is decoded once; when it does not, the decoder keeps working for as long as the animation plays.",
        code: """
        // Plays animated images on its own
        LazyImage(url: url)

        // Or, for control and diagnostics
        let player = AnimatedImagePlayer(
            source: source
        )
        AnimatedImage(player: player)
        """,
        points: [
            .init("Wall clock", "Playback follows the clock rather than the decoder, so an animation always takes as long as it says it does. A frame that is not ready in time is skipped instead of stretching the timeline."),
            .init("Frame buffer", "The budget is in bytes, not frames. When the whole animation fits, every frame is decoded once; below that, the buffer becomes a window that slides ahead of the playhead."),
            .init("Buffer map", "The bar at the top of the overlay is one cell per frame: filled when the frame is decoded, tinted for the frame on screen."),
            .init("Memory warnings", "The player drops its buffer to the minimum when the system issues one. The button does the same thing by hand."),
            .init("Diagnostics", "Everything in the overlay comes from `AnimatedImagePlayer.diagnostics`, which is available in your own app too. The demo samples it ten times a second: a view that redrew on every frame would be measuring itself.")
        ]
    )

    /// Everything that requires the animation to be loaded again from scratch.
    private var reloadID: String {
        "\(image.rawValue)-\(settings.maxBufferSizeMB)-\(settings.isDownsamplingEnabled)-\(settings.playbackRate)-\(settings.repeatsForever)"
    }

    // MARK: Sections

    private var picker: some View {
        Picker("Image", selection: $image) {
            ForEach(DemoAnimation.allCases, id: \.self) {
                Text($0.title).tag($0)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    private var stage: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let player {
                AnimatedImage(player: player)
                    .resizable()
                    .scaledToFit()
            } else if let status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                ProgressView()
            }
        }
        .frame(height: 280)
        .clipped()
        .overlay(alignment: .topTrailing) {
            Button {
                isShowingDiagnostics.toggle()
            } label: {
                Image(systemName: isShowingDiagnostics ? "chart.bar.fill" : "chart.bar")
                    .padding(8)
                    .background(.thinMaterial, in: Circle())
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var transport: some View {
        if let player {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        if player.isPlaying {
                            player.pause()
                        } else if player.isFinished {
                            player.restart()
                        } else {
                            player.play()
                        }
                        diagnostics = player.diagnostics
                    } label: {
                        Label(
                            player.isPlaying ? "Pause" : (player.isFinished ? "Replay" : "Play"),
                            systemImage: player.isPlaying ? "pause.fill" : (player.isFinished ? "arrow.clockwise" : "play.fill")
                        )
                        .frame(width: 110)
                    }
                    .buttonStyle(.bordered)

                    Button("Memory Warning") {
                        // The same call the player makes for itself when the
                        // system issues one.
                        player.reduceMemoryUsage()
                        diagnostics = player.diagnostics
                    }
                    .buttonStyle(.bordered)
                }

                // Scrubbing pauses first: seeking while the clock runs would
                // hand the frame straight back to the animation.
                Slider(
                    value: Binding(
                        get: { Double(diagnostics.currentFrameIndex) },
                        set: {
                            player.pause()
                            player.seek(toFrame: Int($0.rounded()))
                            diagnostics = player.diagnostics
                        }
                    ),
                    in: 0...Double(max(1, player.source.frameCount - 1)),
                    step: 1
                ) {
                    Text("Frame")
                }
                Text("Frame \(diagnostics.currentFrameIndex + 1) of \(player.source.frameCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            DemoExample("Frame buffer", caption: "The memory the decoded frames may use. Drop it below what the animation needs and the buffer becomes a sliding window.") {
                VStack(alignment: .leading) {
                    Slider(value: $settings.maxBufferSizeMB, in: 0.25...32) {
                        Text("Buffer")
                    }
                    Text(String(format: "%.2f MB", settings.maxBufferSizeMB))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            DemoExample("Playback rate") {
                VStack(alignment: .leading) {
                    Slider(value: $settings.playbackRate, in: 0.25...4, step: 0.25) {
                        Text("Rate")
                    }
                    Text(String(format: "%.2f×", settings.playbackRate))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Downsample to 240 px", isOn: $settings.isDownsamplingEnabled)
                .font(.subheadline)
            Toggle("Repeat forever", isOn: $settings.repeatsForever)
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Loading

    private func load() async {
        player = nil
        status = nil
        diagnostics = AnimatedImagePlayer.Diagnostics()
        do {
            let response = try await ImagePipeline.shared.imageTask(with: image.url).response
            guard let source = AnimatedImageSource(container: response.container) else {
                status = "\(image.title) loaded, but it isn't an animated image."
                return
            }
            let player = AnimatedImagePlayer(source: source, options: settings.playerOptions)
            player.play()
            self.player = player
            self.diagnostics = player.diagnostics
        } catch {
            status = "Failed to load: \(error.localizedDescription)"
        }
    }
}

// MARK: - Diagnostics Overlay

/// The overlay itself: the buffer map, then the numbers behind it.
private struct AnimatedImageDiagnosticsView: View {
    let player: AnimatedImagePlayer
    let diagnostics: AnimatedImagePlayer.Diagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            BufferMap(player: player, diagnostics: diagnostics)
            Divider()
            grid
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
    }

    private var header: some View {
        HStack {
            Text("Diagnostics")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if diagnostics.isFullyBuffered {
                DemoBadge("Fully buffered", color: .green)
            } else {
                DemoBadge("Sliding window", color: .orange)
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 6) {
            DiagnosticsRow("Frame", "\(diagnostics.currentFrameIndex + 1) / \(diagnostics.frameCount)")
            DiagnosticsRow("Loops", "\(diagnostics.completedLoopCount)")
            DiagnosticsRow("Buffered", "\(diagnostics.bufferedFrameCount) / \(diagnostics.bufferCapacity) frames · \(demoByteCount(diagnostics.bufferedByteCount))")
            DiagnosticsRow("Decoded", "\(diagnostics.decodedFrameCount) frames")
            DiagnosticsRow("Decode", "\(milliseconds(diagnostics.lastDecodeDuration)) last · \(milliseconds(diagnostics.averageDecodeDuration)) avg · \(milliseconds(diagnostics.maxDecodeDuration)) max")
            DiagnosticsRow("Frame rate", "\(rate(diagnostics.effectiveFrameRate)) of \(rate(player.source.nominalFrameRate)) fps")
            DiagnosticsRow("Displayed", "\(diagnostics.displayedFrameCount) frames in \(seconds(diagnostics.playbackTime))")
            DiagnosticsRow(
                "Skipped",
                "\(diagnostics.skippedFrameCount) behind · \(diagnostics.bufferMissCount) not ready",
                isWarning: diagnostics.skippedFrameCount > 0 || diagnostics.bufferMissCount > 0
            )
            DiagnosticsRow("Size", "\(Int(player.source.size.width))×\(Int(player.source.size.height)) px · \(demoByteCount(player.source.bytesPerFrame)) per frame")
            DiagnosticsRow("Duration", "\(seconds(player.source.duration)) · \(player.source.loopCount == 0 ? "loops forever" : "\(player.source.loopCount) loops")")
        }
    }

    private func milliseconds(_ value: TimeInterval) -> String {
        String(format: "%.1f ms", value * 1000)
    }

    private func seconds(_ value: TimeInterval) -> String {
        String(format: "%.1f s", value)
    }

    private func rate(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

/// One cell per frame: filled when the frame is decoded, outlined when it isn't,
/// and tinted for the frame on screen. It is the buffer policy made visible –
/// a full row means the animation fits in memory, a moving band of filled cells
/// means it doesn't.
private struct BufferMap: View {
    let player: AnimatedImagePlayer
    let diagnostics: AnimatedImagePlayer.Diagnostics

    var body: some View {
        GeometryReader { proxy in
            let count = max(1, diagnostics.frameCount)
            let spacing: CGFloat = count > 60 ? 0.5 : 2
            let width = max(1, (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color(for: index))
                        .frame(width: width)
                }
            }
        }
        .frame(height: 22)
    }

    private func color(for index: Int) -> Color {
        if index == diagnostics.currentFrameIndex {
            return .accentColor
        }
        return player.isFrameBuffered(index) ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08)
    }
}

private struct DiagnosticsRow: View {
    private let title: String
    private let value: String
    private let isWarning: Bool

    init(_ title: String, _ value: String, isWarning: Bool = false) {
        self.title = title
        self.value = value
        self.isWarning = isWarning
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(isWarning ? Color.orange : Color.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Model

private enum DemoAnimation: String, CaseIterable {
    case gif, apng, webp, large

    var title: String {
        switch self {
        case .gif: "GIF"
        case .apng: "APNG"
        case .webp: "WebP"
        case .large: "Large"
        }
    }

    var url: URL {
        switch self {
        case .gif: DemoImages.gif
        case .apng: DemoImages.apng
        case .webp: DemoImages.animatedWebP
        case .large: DemoImages.largeGIF
        }
    }
}

private struct DemoAnimationSettings {
    var maxBufferSizeMB: Double = 10
    var playbackRate: Double = 1
    var isDownsamplingEnabled = false
    var repeatsForever = true

    var playerOptions: AnimatedImagePlayer.Options {
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = Int(maxBufferSizeMB * 1_048_576)
        options.playbackRate = playbackRate
        options.maxPixelSize = isDownsamplingEnabled ? 240 : nil
        options.repeatCount = repeatsForever ? .infinite : .image
        options.scale = 1
        return options
    }
}

#Preview {
    NavigationStack {
        AnimatedImagesDemo()
    }
}
