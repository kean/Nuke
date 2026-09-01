// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI

/// Plays one animated image with live diagnostics: what the window of decoded
/// frames is holding, what each frame costs to decode, and whether playback is
/// keeping up with the wall clock.
///
/// `LazyImage` plays animated images on its own; this screen creates the
/// ``AnimatedImagePlayer`` itself to get at ``AnimatedImagePlayer/diagnostics``.
/// The **Frame Pool** screen is the same thing for a wall of them.
struct AnimatedImagesDemo: View {
    @State private var image: DemoAnimation = .gif
    @State private var settings = Settings()
    @State private var animation: DemoLoadedAnimation?
    /// Sampled on a timer rather than observed: the diagnostics change on every
    /// frame, and a view that redrew that often would be measuring itself.
    @State private var diagnostics = AnimatedImagePlayer.Diagnostics()
    @State private var status: String?

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                Picker("Image", selection: $image) {
                    ForEach(DemoAnimation.available) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                stage
            }

            diagnosticsSection
            bufferSection
            playbackSection
        }
        .safeAreaInset(edge: .bottom) { transport }
        .task(id: reloadKey) { await load() }
        .onReceive(timer) { _ in sample() }
        .navigationTitle("Animated Images")
        .demoInfo(Self.info)
    }

    // MARK: Stage

    @ViewBuilder
    private var stage: some View {
        ZStack {
            if let animation {
                AnimatedImage(player: animation.player, poster: animation.poster)
                    .resizable()
                    .scaledToFit()
            } else if let status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220)
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    }

    /// The scrubber and the buttons, pinned below the list so that they stay
    /// reachable wherever it is scrolled to.
    @ViewBuilder
    private var transport: some View {
        if let animation {
            DemoAnimationTransport(player: animation.player, diagnostics: diagnostics)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var diagnosticsSection: some View {
        if let animation {
            Section {
                DemoDiagnosticsPanel(player: animation.player, diagnostics: diagnostics)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            } header: {
                HStack {
                    Text("Diagnostics")
                    Spacer(minLength: 8)
                    if diagnostics.isFullyBuffered {
                        DemoBadge("Fully buffered", color: .green)
                    } else {
                        DemoBadge("Sliding window", color: .orange)
                    }
                }
            }
        }
    }

    private var bufferSection: some View {
        Section {
            LabeledContent("Budget") {
                DemoMonoLabel(String(format: "%.2f MB", settings.maxBufferSizeMB ?? defaultMaxBufferSizeMB) + (settings.maxBufferSizeMB == nil ? " (default)" : ""))
            }
            Slider(value: Binding(
                get: { settings.maxBufferSizeMB ?? defaultMaxBufferSizeMB },
                set: { settings.maxBufferSizeMB = $0 }
            ), in: 0.25...32) {
                Text("Budget")
            }
            LabeledContent("Frame size") {
                DemoMonoLabel(demoPixelSizeSubtitle(settings.maxPixelSize))
            }
            Picker("Frame size", selection: $settings.maxPixelSize) {
                ForEach(demoMaxPixelSizes, id: \.self) {
                    Text(demoPixelSize($0)).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text("Frame Buffer")
        } footer: {
            Text("The most this player may use, and the longest side its frames are decoded at. Drop the budget below what the animation needs and the buffer becomes a window that slides ahead of the playhead; drop the frame size and every frame costs the square of the scale less.")
        }
    }

    private var playbackSection: some View {
        Section {
            LabeledContent("Rate") {
                DemoMonoLabel(String(format: "%.2f×", settings.playbackRate))
            }
            Slider(value: $settings.playbackRate, in: 0.25...4, step: 0.25) {
                Text("Rate")
            }
            Toggle("Repeat forever", isOn: $settings.repeatsForever)
        } header: {
            Text("Playback")
        } footer: {
            Text("The animation keeps its declared duration; the rate changes how fast the clock runs through it.")
        }
    }

    // MARK: Loading

    /// Everything that requires the animation to be loaded again from scratch.
    private var reloadKey: Settings.ReloadKey {
        settings.reloadKey(for: image)
    }

    private func load() async {
        animation = nil
        status = nil
        let load = await loadDemoAnimations([image], options: settings.playerOptions)
        animation = load.animations.first
        status = load.status
        sample()
    }

    private func sample() {
        diagnostics = animation?.player.diagnostics ?? AnimatedImagePlayer.Diagnostics()
    }

    /// What a player gets when the budget isn't set: a fifth of the pool.
    private var defaultMaxBufferSizeMB: Double {
        Double(AnimatedImageFramePool.shared.defaultMaxBufferSize) / 1_048_576
    }

    // MARK: Model

    private struct Settings {
        /// `nil` for the default, which is a share of the frame pool.
        var maxBufferSizeMB: Double?
        var maxPixelSize: CGFloat?
        var playbackRate: Double = 1
        var repeatsForever = true

        var playerOptions: AnimatedImagePlayer.Options {
            var options = AnimatedImagePlayer.Options()
            options.maxBufferSize = maxBufferSizeMB.map { Int($0 * 1_048_576) }
            options.playbackRate = playbackRate
            options.maxPixelSize = maxPixelSize
            options.repeatCount = repeatsForever ? .infinite : .image
            return options
        }

        /// The settings a new player has to be built for. Everything else takes
        /// effect on the player that is already running.
        struct ReloadKey: Hashable {
            var image: DemoAnimation
            var maxBufferSizeMB: Double?
            var maxPixelSize: CGFloat?
            var playbackRate: Double
            var repeatsForever: Bool
        }

        func reloadKey(for image: DemoAnimation) -> ReloadKey {
            ReloadKey(
                image: image,
                maxBufferSizeMB: maxBufferSizeMB,
                maxPixelSize: maxPixelSize,
                playbackRate: playbackRate,
                repeatsForever: repeatsForever
            )
        }
    }

    fileprivate static let info = DemoInfo(
        "Animated Images",
        "NukeUI decodes the frames of an animated image off the main thread and keeps a bounded number of them in memory. Change the buffer and watch the diagnostics: when the whole animation fits, every frame is decoded once; when it does not, the decoder keeps working for as long as the animation plays.",
        code: """
        // Plays animated images on its own
        LazyImage(url: url)

        // Or, for control and diagnostics
        let player = AnimatedImagePlayer(source: source)
        AnimatedImage(player: player, poster: response.image)
        """,
        points: [
            .init("Frame buffer", "The budget is in bytes of decoded frames – the canvas at four bytes a pixel, not the size of the file – and is a fifth of the frame pool's limit unless you set it. When the whole animation fits, every frame is decoded once; below that, the buffer is the frame on screen and three ahead of it, however large the budget – a window that slides re-decodes every frame each loop no matter how long it is. `maxPixelSize` scales the frames as they are decoded, and a frame costs the square of the scale: half the size is a quarter of the memory."),
            .init("Buffer map", "The bar at the top of the diagnostics is one cell per frame: filled when the frame is decoded, tinted for the frame on screen."),
            .init("Handing over from the still", "Two lines here are worth copying. The player is built with the scale of the image the pipeline decoded, and the view is given that image as its poster. Without the first, the animation changes size the moment it starts playing; without the second, the canvas is blank for as long as the first frame takes to decode."),
            .init("Diagnostics", "Everything here comes from `AnimatedImagePlayer.diagnostics`, which is available in your own app too. The demo samples it ten times a second: a view that redrew on every frame would be measuring itself. The play button doesn't need the timer – the player is an `ObservableObject` and publishes when playback starts, stops, or finishes.")
        ]
    )
}

/// The scrubber, what it is pointing at, and the buttons.
///
/// A view of its own so that it can observe the player: the button reads
/// `isPlaying` and `isFinished` straight off it, while the numbers beside the
/// scrubber move on every frame and come from the sampled diagnostics.
private struct DemoAnimationTransport: View {
    @ObservedObject var player: AnimatedImagePlayer
    let diagnostics: AnimatedImagePlayer.Diagnostics

    var body: some View {
        VStack(spacing: 12) {
            // Scrubbing pauses first: seeking while the clock runs would hand
            // the frame straight back to the animation.
            Slider(
                value: Binding(
                    get: { Double(diagnostics.currentFrameIndex) },
                    set: {
                        player.pause()
                        player.seek(toFrame: Int($0.rounded()))
                    }
                ),
                in: 0...Double(max(1, player.source.frameCount - 1)),
                step: 1
            ) {
                Text("Frame")
            }

            HStack {
                DemoMonoLabel("frame \(diagnostics.currentFrameIndex + 1) of \(diagnostics.frameCount)")
                Spacer()
                DemoMonoLabel("loop \(diagnostics.completedLoopCount)")
            }

            HStack(spacing: 12) {
                Button {
                    if player.isPlaying {
                        player.pause()
                    } else if player.isFinished {
                        player.restart()
                    } else {
                        player.play()
                    }
                } label: {
                    Label(
                        player.isPlaying ? "Pause" : (player.isFinished ? "Replay" : "Play"),
                        systemImage: player.isPlaying ? "pause.fill" : (player.isFinished ? "arrow.clockwise" : "play.fill")
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    // The same call the pool makes for itself when the system
                    // issues a memory warning.
                    AnimatedImageFramePool.shared.reduceMemoryUsage()
                } label: {
                    Label("Free Memory", systemImage: "memorychip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// The numbers behind the animation.
private struct DemoDiagnosticsPanel: View {
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
            DemoDiagnosticsRow("buffer", "\(diagnostics.bufferedFrameCount)/\(diagnostics.bufferCapacity) frames  ·  \(demoByteCount(diagnostics.bufferedByteCount)) of \(demoByteCount(diagnostics.bufferByteLimit))")
            DemoDiagnosticsRow("decoded", "\(diagnostics.decodedFrameCount) frames")
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

#Preview {
    NavigationStack {
        AnimatedImagesDemo()
    }
}
