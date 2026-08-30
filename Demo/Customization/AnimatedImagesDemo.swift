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
    /// The still the decoder produced, handed to the view so that the canvas
    /// isn't blank for as long as the first frame takes to decode.
    @State private var poster: UIImage?
    @State private var diagnostics = AnimatedImagePlayer.Diagnostics()
    @State private var status: String?
    @State private var isShowingDiagnostics = true
    @State private var isShowingInfo = false
    @State private var detent: PresentationDetent = DemoAnimationConsole.collapsed

    /// Sampling the diagnostics rather than observing them: they change on every
    /// frame, and a view that redrew that often would be measuring itself. The
    /// player publishes the things that don't – it starts, it stops, it
    /// finishes – so the transport doesn't wait for a tick to catch up.
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
        let player = AnimatedImagePlayer(source: source)
        AnimatedImage(player: player, poster: response.image)
        """,
        points: [
            .init("Wall clock", "Playback follows the clock rather than the decoder, so an animation always takes as long as it says it does. A frame that is not ready in time is skipped instead of stretching the timeline."),
            .init("Frame buffer", "The budget is in bytes, not frames. When the whole animation fits, every frame is decoded once; below that, the buffer becomes a window that slides ahead of the playhead."),
            .init("Frame size", "`maxPixelSize` scales the frames as they are decoded, and a frame costs the square of the scale: half the size is a quarter of the memory. `AnimatedImageView` picks one from its own bounds; this screen builds the player by hand, so the size is yours to choose. The diagnostics show what the frames were authored at and what they are decoded at."),
            .init("Buffer map", "The bar at the top of the diagnostics is one cell per frame: filled when the frame is decoded, tinted for the frame on screen."),
            .init("Memory warnings", "The player drops its buffer to the minimum when the system issues one, and the button does the same thing by hand. The buffer isn't shrunk for good: the window it was sized for comes back a minute later, or right away if the app is backgrounded and returns – send the demo to the background and come back to watch the map refill."),
            .init("Handing over from the still", "Two lines here are worth copying. The player is built with the scale of the image the pipeline decoded, and the view is given that image as its poster. Without the first, the animation changes size the moment it starts playing; without the second, the canvas is blank for as long as the first frame takes to decode."),
            .init("Layout", "`AnimatedImage` reports the size an `Image` would, so the usual layout modifiers apply. `.fit` reports the size the frames occupy rather than the box they were offered, which is what makes the rounded background wrap the animation instead of the space around it."),
            .init("Diagnostics", "Everything here comes from `AnimatedImagePlayer.diagnostics`, which is available in your own app too. The demo samples it ten times a second: a view that redrew on every frame would be measuring itself. The play button doesn't need the timer – the player is an `ObservableObject` and publishes when playback starts, stops, or finishes.")
        ]
    )

    /// Everything that requires the animation to be loaded again from scratch.
    private var reloadID: String {
        "\(image.rawValue)-\(settings.maxBufferSizeMB)-\(settings.maxPixelSize.rawValue)-\(settings.playbackRate)-\(settings.repeatsForever)"
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                Picker("Image", selection: $image) {
                    ForEach(DemoAnimation.available, id: \.self) {
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
                AnimatedImage(player: player, poster: poster)
                    .resizable(contentMode: settings.contentMode)
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
        poster = nil
        status = nil
        diagnostics = AnimatedImagePlayer.Diagnostics()
        guard let url = image.url else {
            status = "There is no \(image.title) image on this platform."
            return
        }
        do {
            let response = try await ImagePipeline.shared.imageTask(with: url).response
            guard let source = AnimatedImageSource(container: response.container) else {
                status = "\(image.title) loaded, but it isn't an animated image."
                return
            }
            var options = settings.playerOptions
            // The scale of the image the pipeline decoded. `AnimatedImageView`
            // does this for the players it makes; a player built by hand has to
            // be told, or the animation changes size the moment it takes over
            // from the still.
            options.scale = response.image.scale
            let player = AnimatedImagePlayer(source: source, options: options)
            player.play()
            self.poster = response.image
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

    /// Tall enough for the whole transport and the first section header under
    /// it, which is what says there is more to pull up.
    static let collapsedHeight: CGFloat = 208
    static let collapsed = PresentationDetent.height(collapsedHeight)

    var body: some View {
        VStack(spacing: 0) {
            transport
                .padding(.horizontal, 20)
                // The drag indicator sits in the first few points of the sheet;
                // the transport starts below it rather than under it.
                .padding(.top, 22)
                .padding(.bottom, 16)
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
            DemoAnimationTransport(player: player, diagnostics: diagnostics)
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
                LabeledContent("Frame size") {
                    DemoMonoLabel(settings.maxPixelSize.subtitle)
                }
                Picker("Frame size", selection: $settings.maxPixelSize) {
                    ForEach(DemoMaxPixelSize.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Frame Buffer")
            } footer: {
                Text("The memory the decoded frames may use, and the longest side they are decoded at. Drop the budget below what the animation needs and the buffer becomes a sliding window; drop the frame size and every frame costs the square of the scale less.")
            }

            Section {
                Picker("Content mode", selection: $settings.contentMode) {
                    Text("Fit").tag(ContentMode.fit)
                    Text("Fill").tag(ContentMode.fill)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Layout")
            } footer: {
                Text("AnimatedImage sizes itself the way Image does. Fit takes the size the frames occupy, so a background or a clip shape wraps the animation; fill covers the space it is offered and clips what hangs over the edge.")
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

/// The scrubber, what it is pointing at, and the buttons – in that order, so
/// that reading down the transport goes from the animation to the controls
/// rather than stepping over them.
///
/// A view of its own so that it can observe the player. The button reads
/// `isPlaying` and `isFinished` straight off it and is redrawn when they
/// change, which is what the player publishes; the numbers beside the scrubber
/// move on every frame and come from the sampled diagnostics instead.
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
                    // The same call the player makes for itself when the system
                    // issues a memory warning.
                    player.reduceMemoryUsage()
                } label: {
                    Label("Free Memory", systemImage: "memorychip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
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
            DiagnosticsRow("buffer", "\(diagnostics.bufferedFrameCount)/\(diagnostics.bufferCapacity) frames  ·  \(demoByteCount(diagnostics.bufferedByteCount)) of \(demoByteCount(player.options.maxBufferSize))")
            DiagnosticsRow("decoded", "\(diagnostics.decodedFrameCount) frames")
            DiagnosticsRow("decode", "\(milliseconds(diagnostics.lastDecodeDuration)) last  ·  \(milliseconds(diagnostics.averageDecodeDuration)) avg  ·  \(milliseconds(diagnostics.maxDecodeDuration)) max")
            DiagnosticsRow("fps", "\(rate(diagnostics.effectiveFrameRate)) of \(rate(player.source.nominalFrameRate))")
            DiagnosticsRow("shown", "\(diagnostics.displayedFrameCount) frames in \(seconds(diagnostics.playbackTime))")
            DiagnosticsRow(
                "missed",
                "\(diagnostics.skippedFrameCount) behind  ·  \(diagnostics.bufferMissCount) not ready",
                tint: diagnostics.skippedFrameCount > 0 || diagnostics.bufferMissCount > 0 ? .orange : nil
            )
            DiagnosticsRow("size", size, tint: decodedSize == nil ? nil : .accentColor)
            DiagnosticsRow("cost", "\(demoByteCount(bytesPerDecodedFrame))/frame  ·  \(demoByteCount(player.source.data.count)) encoded")
            DiagnosticsRow("length", "\(seconds(player.source.duration))  ·  \(player.source.loopCount == 0 ? "loops forever" : "\(player.source.loopCount) loops")")
        }
    }

    /// The canvas the animation declares, and – when the frames are being
    /// scaled down – the size they are actually decoded at.
    private var size: String {
        let canvas = "\(pixels(player.source.size)) px"
        guard let decodedSize else { return canvas }
        return "\(canvas) → \(pixels(decodedSize)) px"
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

    private func pixels(_ size: CGSize) -> String {
        "\(Int(size.width))×\(Int(size.height))"
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
    /// Set for the numbers worth looking at right now: orange for the frames
    /// playback couldn't keep up with, the accent color for a setting that is
    /// visibly doing something.
    private let tint: Color?

    init(_ title: String, _ value: String, tint: Color? = nil) {
        self.title = title
        self.value = value
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .foregroundStyle(tint ?? Color.primary)
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
    case gif, apng, webp, heic, large

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

private struct DemoAnimationSettings {
    var maxBufferSizeMB: Double = 10
    var playbackRate: Double = 1
    var maxPixelSize: DemoMaxPixelSize = .full
    var repeatsForever = true
    /// The only setting here that isn't a player option: it belongs to the
    /// view, so changing it doesn't reload the animation.
    var contentMode: ContentMode = .fit

    var playerOptions: AnimatedImagePlayer.Options {
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = Int(maxBufferSizeMB * 1_048_576)
        options.playbackRate = playbackRate
        options.maxPixelSize = maxPixelSize.value
        options.repeatCount = repeatsForever ? .infinite : .image
        return options
    }
}

/// The longest side the frames are decoded at.
///
/// The biggest memory lever there is: a frame costs the square of the scale, so
/// decoding at half the size is a quarter of the memory and four times as many
/// frames in the same budget. ``AnimatedImageView`` derives one from its own
/// size; a player built by hand, like this screen's, takes what it is given.
private enum DemoMaxPixelSize: Int, CaseIterable, Identifiable {
    case full = 0
    case small = 120
    case medium = 240
    case large = 480

    var id: Int { rawValue }

    var title: String { self == .full ? "Full" : "\(rawValue)" }

    var subtitle: String { self == .full ? "as authored" : "\(rawValue) px" }

    var value: CGFloat? { self == .full ? nil : CGFloat(rawValue) }
}

#Preview {
    NavigationStack {
        AnimatedImagesDemo()
    }
}
