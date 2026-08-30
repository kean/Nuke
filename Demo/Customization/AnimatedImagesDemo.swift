// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI

/// Plays animated images with live diagnostics: what the frame buffer is
/// holding, what each frame costs to decode, and whether playback is keeping up
/// with the wall clock.
///
/// ```swift
/// LazyImage(url: url) // Plays animated images on its own
/// ```
///
/// This screen does it the long way – it creates the ``AnimatedImagePlayer``
/// itself – because that is what gives it access to
/// ``AnimatedImagePlayer/diagnostics``.
///
/// The layout is a stage and a console: the picker and the animation stay put
/// at the top, and everything that scrolls lives in the sheet below them. The
/// two never overlap, so there is only ever one thing to scroll.
struct AnimatedImagesDemo: View {
    @State private var image: DemoAnimation = .gif
    @State private var settings = DemoAnimationSettings()
    @State private var player: AnimatedImagePlayer?
    @State private var diagnostics = AnimatedImagePlayer.Diagnostics()
    @State private var status: String?
    @State private var isShowingDiagnostics = true
    @State private var isShowingInfo = false
    @State private var detent: PresentationDetent = DemoAnimationConsole.collapsed

    /// Sampling the player rather than observing it: the diagnostics change on
    /// every frame, and a view that redrew that often would be measuring itself.
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        stage
            .task(id: reloadID) { await load() }
            .onReceive(timer) { _ in
                guard let player else { return }
                diagnostics = player.diagnostics
            }
            .sheet(isPresented: .constant(true)) {
                DemoAnimationConsole(
                    player: player,
                    diagnostics: diagnostics,
                    settings: $settings,
                    detent: $detent,
                    isShowingDiagnostics: $isShowingDiagnostics,
                    isShowingInfo: $isShowingInfo
                )
            }
            .demoInfoButton(isPresented: $isShowingInfo)
    }

    fileprivate static let info = DemoInfo(
        "Animated Images",
        "NukeUI decodes the frames of an animated image off the main thread and keeps a bounded number of them in memory. Change the buffer and watch the diagnostics: when the whole animation fits, every frame is decoded once; when it does not, the decoder keeps working for as long as the animation plays.",
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
            .init("Buffer map", "The bar at the top of the diagnostics is one cell per frame: filled when the frame is decoded, tinted for the frame on screen."),
            .init("Memory warnings", "The player drops its buffer to the minimum when the system issues one. The button does the same thing by hand."),
            .init("Diagnostics", "Everything here comes from `AnimatedImagePlayer.diagnostics`, which is available in your own app too. The demo samples it ten times a second: a view that redrew on every frame would be measuring itself.")
        ]
    )

    /// Everything that requires the animation to be loaded again from scratch.
    private var reloadID: String {
        "\(image.rawValue)-\(settings.maxBufferSizeMB)-\(settings.isDownsamplingEnabled)-\(settings.playbackRate)-\(settings.repeatsForever)"
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                Picker("Image", selection: $image) {
                    ForEach(DemoAnimation.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.segmented)

                canvas
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .frame(height: stageHeight(in: proxy), alignment: .top)
            .animation(.snappy, value: detent)
        }
        .background(Color(.systemGroupedBackground))
    }

    /// The room the console leaves for the animation.
    ///
    /// The console is presented over the screen rather than beside it, so the
    /// stage has to keep clear of it by hand. Pulling the sheet up shrinks the
    /// animation instead of covering it, which is the point of the screen: the
    /// settings that change the animation are no use without it in view.
    private func stageHeight(in proxy: GeometryProxy) -> CGFloat {
        let console = detent == DemoAnimationConsole.collapsed
            ? DemoAnimationConsole.collapsedHeight
            // Everything above `.medium` covers the stage anyway, so the size
            // it settles on there is the smallest one worth laying out.
            : proxy.size.height / 2
        return max(200, proxy.size.height - console)
    }

    private var canvas: some View {
        ZStack {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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

// MARK: - Console

/// The transport, the diagnostics, and the settings.
///
/// The transport is pinned above the list rather than being its first row, so
/// that the sheet pushed all the way down is always the same thing – the play
/// button and the scrubber – no matter where the list is scrolled to.
private struct DemoAnimationConsole: View {
    let player: AnimatedImagePlayer?
    let diagnostics: AnimatedImagePlayer.Diagnostics
    @Binding var settings: DemoAnimationSettings
    @Binding var detent: PresentationDetent
    @Binding var isShowingDiagnostics: Bool
    /// The screen's own sheet covers the one the toolbar button would present,
    /// so the explanation is presented from here instead.
    @Binding var isShowingInfo: Bool

    /// Tall enough for the transport and the first section header under it,
    /// which is what says there is more to pull up.
    static let collapsedHeight: CGFloat = 140
    static let collapsed = PresentationDetent.height(collapsedHeight)

    var body: some View {
        VStack(spacing: 0) {
            transport
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 14)
            list
        }
        .presentationDetents([Self.collapsed, .medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
        .demoSheetBackgroundInteraction()
        .sheet(isPresented: $isShowingInfo) {
            DemoInfoSheet(info: AnimatedImagesDemo.info)
        }
    }

    // MARK: Transport

    @ViewBuilder
    private var transport: some View {
        if let player {
            VStack(spacing: 10) {
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
                        // The same call the player makes for itself when the
                        // system issues a memory warning.
                        player.reduceMemoryUsage()
                    } label: {
                        Label("Free Memory", systemImage: "memorychip")
                            .frame(maxWidth: .infinity)
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
            }
        } else {
            Text("Loading…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: List

    private var list: some View {
        List {
            if let player {
                Section {
                    if isShowingDiagnostics {
                        DemoDiagnosticsPanel(player: player, diagnostics: diagnostics)
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                } header: {
                    diagnosticsHeader
                }
            }

            Section {
                LabeledContent("Budget") {
                    DemoMonoLabel(String(format: "%.2f MB", settings.maxBufferSizeMB))
                }
                Slider(value: $settings.maxBufferSizeMB, in: 0.25...32) {
                    Text("Budget")
                }
                Toggle("Downsample to 240 px", isOn: $settings.isDownsamplingEnabled)
            } header: {
                Text("Frame Buffer")
            } footer: {
                Text("The memory the decoded frames may use. Drop it below what the animation needs and the buffer becomes a sliding window.")
            }

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
        .listStyle(.insetGrouped)
    }

    private var diagnosticsHeader: some View {
        Button {
            withAnimation(.snappy) { isShowingDiagnostics.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text("Diagnostics")
                Spacer(minLength: 8)
                if diagnostics.isFullyBuffered {
                    DemoBadge("Fully buffered", color: .green)
                } else {
                    DemoBadge("Sliding window", color: .orange)
                }
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(isShowingDiagnostics ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isShowingDiagnostics ? "Hide diagnostics" : "Show diagnostics")
    }
}

private extension View {
    /// Keeps the stage behind the console interactive, so the animation can be
    /// scrubbed and switched while the settings change.
    @ViewBuilder
    func demoSheetBackgroundInteraction() -> some View {
        if #available(iOS 16.4, *) {
            presentationBackgroundInteraction(.enabled(upThrough: .medium))
        } else {
            self
        }
    }
}

// MARK: - Diagnostics

/// The numbers behind the animation.
private struct DemoDiagnosticsPanel: View {
    let player: AnimatedImagePlayer
    let diagnostics: AnimatedImagePlayer.Diagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BufferMap(player: player, diagnostics: diagnostics)
            Divider()
            grid
        }
    }

    private var grid: some View {
        VStack(spacing: 6) {
            DiagnosticsRow("frame", "\(diagnostics.currentFrameIndex + 1)/\(diagnostics.frameCount)  ·  loop \(diagnostics.completedLoopCount)")
            DiagnosticsRow("buffer", "\(diagnostics.bufferedFrameCount)/\(diagnostics.bufferCapacity) frames  ·  \(demoByteCount(diagnostics.bufferedByteCount))")
            DiagnosticsRow("decoded", "\(diagnostics.decodedFrameCount) frames")
            DiagnosticsRow("decode", "\(milliseconds(diagnostics.lastDecodeDuration)) last  ·  \(milliseconds(diagnostics.averageDecodeDuration)) avg  ·  \(milliseconds(diagnostics.maxDecodeDuration)) max")
            DiagnosticsRow("fps", "\(rate(diagnostics.effectiveFrameRate)) of \(rate(player.source.nominalFrameRate))")
            DiagnosticsRow("shown", "\(diagnostics.displayedFrameCount) frames in \(seconds(diagnostics.playbackTime))")
            DiagnosticsRow(
                "missed",
                "\(diagnostics.skippedFrameCount) behind  ·  \(diagnostics.bufferMissCount) not ready",
                isWarning: diagnostics.skippedFrameCount > 0 || diagnostics.bufferMissCount > 0
            )
            DiagnosticsRow("size", "\(Int(player.source.size.width))×\(Int(player.source.size.height)) px  ·  \(demoByteCount(player.source.bytesPerFrame))/frame")
            DiagnosticsRow("length", "\(seconds(player.source.duration))  ·  \(player.source.loopCount == 0 ? "loops forever" : "\(player.source.loopCount) loops")")
        }
    }

    private func milliseconds(_ value: TimeInterval) -> String {
        String(format: "%.1fms", value * 1000)
    }

    private func seconds(_ value: TimeInterval) -> String {
        String(format: "%.1fs", value)
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
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color(for: index))
                        .frame(width: width)
                }
            }
        }
        .frame(height: 24)
    }

    private func color(for index: Int) -> Color {
        if index == diagnostics.currentFrameIndex {
            return .accentColor
        }
        return player.isFrameBuffered(index) ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.07)
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .foregroundStyle(isWarning ? Color.orange : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
    }
}

private struct DemoMonoLabel: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
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
