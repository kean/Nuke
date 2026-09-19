// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI
import UIKit

/// The first sixty seconds with Nuke: the snippets the README and the
/// documentation open with, each running under its code.
///
/// ```swift
/// let imageTask = ImagePipeline.shared.imageTask(with: url)
/// for await progress in imageTask.progress {
///     // Update progress
/// }
/// imageView.image = try await imageTask.image
/// ```
///
/// All three load one URL through the shared pipeline, in the order of the
/// screens that follow in the catalog, and one after the other: `LazyImage`
/// starts once the pipeline has returned the image, and `loadImage(with:into:)`
/// once `LazyImage` has shown it. So the two NukeUI views find the image in
/// the memory cache. They look there before they create a task, which is why
/// they finish together, with no task.
///
/// The app opens on it. On an iPad it is the pane beside the catalog; on a
/// phone, the first row.
struct GettingStartedDemo: View {
    /// Whether it is the pane beside the catalog on an iPad rather than a
    /// screen of its own. The catalog has the navigation bar, so the pane has
    /// its own title and question mark.
    var isPane = false

    @State private var model = GettingStartedModel()
    @State private var width: CGFloat = 0
    @State private var isShowingInfo = false

    var body: some View {
        let arrangement = Arrangement(width: width)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isPane {
                    header
                }
                Text("The snippets the README and the documentation open with, each running under its code. All three load the same photo through `ImagePipeline.shared`.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                panes(arrangement)

                footer
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width - 32 } action: { width = $0 }
        }
        .background(Color(.systemGroupedBackground))
        // Starts over with each run, and when the screen comes back to a
        // pipeline load it left unfinished.
        .task(id: model.run) {
            await model.start()
        }
        .modifier(InfoModifier(isPane: isPane, isPresented: $isShowingInfo))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DemoScreen.gettingStarted.title)
                    .font(.title2.weight(.bold))
                Text(DemoScreen.gettingStarted.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                isShowingInfo = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .imageScale(.large)
            }
            .accessibilityLabel("About This Screen")
        }
    }

    private func panes(_ arrangement: Arrangement) -> some View {
        let layout = arrangement == .columns
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            : AnyLayout(VStackLayout(spacing: 16))
        return layout {
            GettingStartedPane(
                number: 1,
                title: "ImagePipeline",
                module: "Nuke · async/await",
                code: """
                let imageTask = ImagePipeline.shared
                    .imageTask(with: url)
                for await progress in imageTask.progress {
                    // Update progress
                }
                imageView.image = try await imageTask.image
                """,
                status: model.status(of: .pipeline),
                next: .imagePipeline,
                arrangement: arrangement
            ) {
                ImageViewRepresentable(imageView: model.pipelineImageView)
                    .overlay(alignment: .bottom) {
                        if let progress = model.progress {
                            ProgressView(value: progress.fraction)
                                .padding(12)
                        }
                    }
            }

            GettingStartedPane(
                number: 2,
                title: "LazyImage",
                module: "NukeUI · SwiftUI",
                code: """
                LazyImage(url: url) { state in
                    state.image?.resizable().scaledToFit()
                }
                """,
                status: model.status(of: .lazyImage),
                next: .lazyImage,
                arrangement: arrangement
            ) {
                if model.hasStarted(.lazyImage) {
                    LazyImage(url: model.url) { state in
                        state.image?.resizable().scaledToFit()
                    }
                    .onStart { _ in model.lazyImageDidStart() }
                    .onCompletion { model.lazyImageDidComplete($0) }
                    .id(model.run)
                }
            }

            GettingStartedPane(
                number: 3,
                title: "UIImageView",
                module: "NukeUI · UIKit",
                code: """
                NukeUI.loadImage(with: url, into: imageView)
                """,
                status: model.status(of: .imageView),
                next: .uikitViews,
                arrangement: arrangement
            ) {
                ImageViewRepresentable(imageView: model.imageView)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Each starts once the one before it has the image, so 2 and 3 find it in the memory cache: nothing is downloaded or decoded again, and neither creates a task.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Run Again", systemImage: "arrow.clockwise") {
                model.runAgain()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Text("Takes the photo out of the memory cache, then loads it the three ways again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static let info = DemoInfo(
        "Getting Started",
        "Three ways to load an image, the way the README and the documentation start: `ImagePipeline` with async/await, `LazyImage` in SwiftUI, and `loadImage(with:into:)` with a `UIImageView`. Each runs under its code, in the order of the screens that follow in the catalog.",
        code: """
        // Nuke
        let image = try await ImagePipeline.shared
            .image(for: url)

        // NukeUI, in SwiftUI
        LazyImage(url: url)

        // NukeUI, in UIKit
        NukeUI.loadImage(with: url,
                         into: imageView)
        """,
        points: [
            .init("One pipeline", "All three load through `ImagePipeline.shared`, which keeps images in memory and, through `URLCache`, the downloaded data on disk. There is nothing to set up: an app can start with the shared pipeline and configure its own later."),
            .init("One image", "The three load the same URL, one after the other. The first puts the image in the memory cache, and the other two find it there, so nothing is downloaded or decoded again. `LazyImage` and `loadImage(with:into:)` look in the memory cache before they create a task, and show the image in the same update, with no placeholder in between."),
            .init("Progress", "`imageTask(with:)` returns the task at once, and its `progress` reports the bytes as they arrive. When all you need is the image, `try await ImagePipeline.shared.image(for: url)` does it in one line."),
            .init("Natural size", "Without a closure, `LazyImage(url:)` shows the image at its natural size, as `AsyncImage` does: this 1440×960 photo would be 1440 points wide. The closure makes it resizable. It gets the state, with the image, the error, and the progress, so it can show a placeholder or a failure as well."),
            .init("NukeUI.loadImage", "The UIKit guide puts the module's name in front of `loadImage`. Inside a type that has a `loadImage` method of its own, Swift would find that method first."),
            .init("Cancellation", "`LazyImage` cancels its request when it disappears, and `loadImage(with:into:)` when its image view goes away or starts another load. Cancelling the Swift task that awaits `imageTask.image` cancels the image task."),
            .init("Where it came from", "The line under each image is `ImageResponse.cacheType`. It is `nil` for an image the data loader returned, whether it was downloaded or read from `URLCache`.")
        ]
    )

    /// The question mark in the navigation bar, or, for the pane, the sheet
    /// for the button in its header.
    private struct InfoModifier: ViewModifier {
        let isPane: Bool
        @Binding var isPresented: Bool

        func body(content: Content) -> some View {
            if isPane {
                content.sheet(isPresented: $isPresented) {
                    DemoInfoSheet(info: GettingStartedDemo.info)
                }
            } else {
                content.demoInfo(GettingStartedDemo.info)
            }
        }
    }
}

/// How the panes are laid out for the width there is.
private enum Arrangement {
    /// The panes one under another, the code over the image: a phone, or the
    /// pane beside the catalog on an iPad.
    case stacked
    /// The panes one under another, the code beside the image.
    case rows
    /// The panes side by side, the code over the image.
    case columns

    init(width: CGFloat) {
        switch width {
        case ..<600: self = .stacked
        case ..<1100: self = .rows
        default: self = .columns
        }
    }
}

// MARK: - Pane

/// A snippet, the image it loaded, where the image came from, and the screen
/// that goes further.
private struct GettingStartedPane<Result: View>: View {
    let number: Int
    let title: String
    let module: String
    let code: String
    let status: GettingStartedModel.Status
    let next: DemoScreen
    let arrangement: Arrangement
    @ViewBuilder let result: () -> Result

    var body: some View {
        let layout = arrangement == .rows
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        VStack(alignment: .leading, spacing: 12) {
            header
            layout {
                // Side by side, the images start at the same height.
                GettingStartedCode(code, reservedLineCount: arrangement == .columns ? 6 : nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    stage
                    DemoMonoLabel(status.text, tint: status.isFailure ? .red : nil)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: arrangement == .rows ? 300 : nil)
            }
            Divider()
            NavigationLink(value: DemoRoute.screen(next)) {
                HStack {
                    Text(next.title)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                }
                .font(.subheadline)
                .contentShape(Rectangle())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// The image at the photo's own aspect ratio, whatever the width.
    private var stage: some View {
        Color.clear
            .aspectRatio(3 / 2, contentMode: .fit)
            .overlay {
                ZStack {
                    Color(.secondarySystemBackground)
                    result()
                    switch status.phase {
                    case .waiting:
                        Text("after \(number - 1)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    case .loading:
                        if number > 1 {
                            ProgressView()
                        }
                    case .failed:
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.red)
                    case .finished:
                        EmptyView()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// A snippet at the largest size at which the longest line of all three fits,
/// so that the code reads whole in a narrow pane too and the panes match;
/// below that, it scrolls sideways.
private struct GettingStartedCode: View {
    let code: String
    let reservedLineCount: Int?

    init(_ code: String, reservedLineCount: Int? = nil) {
        self.code = code
        self.reservedLineCount = reservedLineCount
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            text(.footnote)
            text(.caption)
            text(.caption2)
            ScrollView(.horizontal, showsIndicators: false) {
                text(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func text(_ style: Font.TextStyle) -> some View {
        ZStack(alignment: .topLeading) {
            Text(Self.longestLine)
                .hidden()
            Text(code)
                .lineLimit(reservedLineCount ?? 100, reservesSpace: reservedLineCount != nil)
                .textSelection(.enabled)
        }
        .font(.system(style, design: .monospaced))
        .fixedSize()
        .padding(10)
    }

    private static let longestLine = "imageView.image = try await imageTask.image"
}

/// A `UIImageView` that the code, not SwiftUI, gives its image, which is how
/// the snippets write it. It takes the size it is offered rather than the
/// size of its image.
private struct ImageViewRepresentable: UIViewRepresentable {
    let imageView: UIImageView

    func makeUIView(context: Context) -> UIImageView {
        imageView
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        // Do nothing
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }
}

// MARK: - Model

/// Runs the three loads in turn and says where each image came from.
@MainActor @Observable
private final class GettingStartedModel {
    enum Step: Comparable {
        case pipeline
        case lazyImage
        case imageView
    }

    struct Status {
        enum Phase {
            case waiting, loading, finished, failed
        }

        var phase: Phase
        var text: String

        var isFailure: Bool { phase == .failed }
    }

    let url = DemoImages.landscape
    let pipelineImageView = GettingStartedModel.makeImageView()
    let imageView = GettingStartedModel.makeImageView()

    /// Goes up with each run. The `LazyImage` of a run is made for it.
    private(set) var run = 0
    /// The last step started, or `nil` before the first.
    private(set) var step: Step?
    /// The download progress of the pipeline's task, while it runs.
    private(set) var progress: ImageTask.Progress?
    private var finished: [Step: Status] = [:]
    private var lazyImageStartDate: Date?

    func hasStarted(_ step: Step) -> Bool {
        self.step.map { $0 >= step } ?? false
    }

    func status(of step: Step) -> Status {
        if let status = finished[step] {
            return status
        }
        guard hasStarted(step) else {
            return Status(phase: .waiting, text: "–")
        }
        if step == .pipeline, let progress, progress.total > 0 {
            return Status(phase: .loading, text: "loading · \(demoByteCount(progress.completed)) of \(demoByteCount(progress.total))")
        }
        return Status(phase: .loading, text: "loading")
    }

    /// Loads the image the way the README's first snippet does, then starts
    /// the `LazyImage`, which starts the image view when it is done.
    func start() async {
        guard step == nil else {
            return
        }
        let run = self.run
        step = .pipeline
        let startDate = Date()
        let status: Status
        do {
            let imageTask = ImagePipeline.shared.imageTask(with: url)
            for await progress in imageTask.progress {
                self.progress = progress
            }
            pipelineImageView.image = try await imageTask.image
            // The same task again, for the line under the image: every caller
            // gets the same outcome.
            let response = try await imageTask.response
            status = Self.status(of: response, bytes: progress?.total, since: startDate, hasTask: true)
        } catch {
            guard run == self.run else {
                return
            }
            guard !Task.isCancelled else {
                // The screen went away. It starts over when it is back.
                step = nil
                progress = nil
                return
            }
            status = Self.failure(error)
        }
        guard run == self.run else {
            return
        }
        progress = nil
        finished[.pipeline] = status
        step = .lazyImage
    }

    func lazyImageDidStart() {
        lazyImageStartDate = Date()
    }

    func lazyImageDidComplete(_ result: Result<ImageResponse, ImagePipeline.Error>) {
        // The view loads again each time it appears: the first result is the
        // one that counts.
        guard step != nil, finished[.lazyImage] == nil else {
            return
        }
        let startDate = lazyImageStartDate
        lazyImageStartDate = nil
        switch result {
        case .success(let response):
            finished[.lazyImage] = Self.status(of: response, bytes: nil, since: startDate, hasTask: startDate != nil)
        case .failure(let error):
            finished[.lazyImage] = Self.failure(error)
        }
        loadIntoImageView()
    }

    private func loadIntoImageView() {
        step = .imageView
        let run = self.run
        let startDate = Date()
        // For an image in the memory cache, the completion is called before
        // `loadImage` returns, and there is no task.
        NukeUI.loadImage(with: url, into: imageView) { [weak self] result in
            guard let self, self.run == run else { return }
            switch result {
            case .success(let response):
                self.finished[.imageView] = Self.status(of: response, bytes: nil, since: startDate, hasTask: response.cacheType != .memory)
            case .failure(let error):
                self.finished[.imageView] = Self.failure(error)
            }
        }
    }

    /// Takes the photo out of the memory cache, and nothing else, and loads
    /// it the three ways again.
    func runAgain() {
        ImagePipeline.shared.cache.removeCachedImage(for: ImageRequest(url: url), caches: [.memory])
        NukeUI.cancelRequest(for: imageView)
        pipelineImageView.image = nil
        imageView.image = nil
        progress = nil
        finished = [:]
        lazyImageStartDate = nil
        step = nil
        run += 1
    }

    private static func status(of response: ImageResponse, bytes: Int64?, since startDate: Date?, hasTask: Bool) -> Status {
        var parts = [response.demoSource]
        if let bytes, bytes > 0, response.cacheType == nil {
            parts.append(demoByteCount(bytes))
        }
        if hasTask, let startDate {
            parts.append(time(Date().timeIntervalSince(startDate)))
        } else if !hasTask {
            parts.append("no task")
        }
        return Status(phase: .finished, text: parts.joined(separator: " · "))
    }

    private static func failure(_ error: any Error) -> Status {
        Status(phase: .failed, text: "failed · \(summary(of: error))")
    }

    /// The error's case, or what the loader said, short enough for a line.
    private static func summary(of error: any Error) -> String {
        (error as? ImagePipeline.Error)?.demoSummary ?? error.localizedDescription
    }

    private static func time(_ value: TimeInterval) -> String {
        value < 0.01 ? demoMilliseconds(value) : demoDuration(value)
    }

    private static func makeImageView() -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }
}

#Preview {
    NavigationStack {
        GettingStartedDemo()
            .demoDestinations()
    }
}
