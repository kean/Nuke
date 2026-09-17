// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// The explanation of a demo screen: a summary, a snippet of the API it is
/// about, and the details that are worth knowing. Presented in a sheet from the
/// question mark in the toolbar.
struct DemoInfo {
    let title: String
    let summary: LocalizedStringKey
    var code: String?
    var points: [Point] = []

    init(_ title: String, _ summary: LocalizedStringKey, code: String? = nil, points: [Point] = []) {
        self.title = title
        self.summary = summary
        self.code = code
        self.points = points
    }

    /// One thing worth knowing about the screen.
    struct Point: Identifiable {
        let title: String
        let text: LocalizedStringKey

        var id: String { title }

        init(_ title: String, _ text: LocalizedStringKey) {
            self.title = title
            self.text = text
        }
    }
}

extension View {
    /// Adds a question mark button to the toolbar that presents ``DemoInfo``.
    func demoInfo(_ info: DemoInfo) -> some View {
        modifier(DemoInfoModifier(info: info))
    }

    /// Adds the question mark button without the sheet, for a screen that keeps
    /// a sheet of its own on display and has to present ``DemoInfoSheet`` from
    /// inside it – iOS drops the second sheet of a screen.
    ///
    /// The switch of the pipeline HUD goes beside it, which puts it on every
    /// screen.
    func demoInfoButton(isPresented: Binding<Bool>) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                DemoHUDToggle()
            }
            ToolbarItem(placement: .topBarTrailing) {
                DemoInfoButton(isPresented: isPresented)
            }
        }
    }
}

private struct DemoInfoModifier: ViewModifier {
    let info: DemoInfo

    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .demoInfoButton(isPresented: $isPresented)
            .sheet(isPresented: $isPresented) {
                DemoInfoSheet(info: info)
            }
    }
}

private struct DemoInfoButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "questionmark")
        }
        .accessibilityLabel("About This Screen")
    }
}

struct DemoInfoSheet: View {
    let info: DemoInfo

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(info.summary)
                        .font(.body)
                        .foregroundStyle(.primary)

                    if let code = info.code {
                        DemoCodeBlock(code)
                    }

                    if !info.points.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(info.points) { point in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(point.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(point.text)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle(info.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// A snippet of Swift, shown the way the documentation shows it.
struct DemoCodeBlock: View {
    private let code: String

    init(_ code: String) {
        self.code = code
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A labeled example: a title, an optional caption, and the view itself.
struct DemoExample<Content: View>: View {
    private let title: String
    private let caption: String?
    private let content: Content

    init(_ title: String, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
    }
}

/// A number or a measurement, in the monospaced style every figure in the demo
/// is written in.
struct DemoMonoLabel: View {
    private let text: String
    private let tint: Color?

    init(_ text: String, tint: Color? = nil) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(tint ?? .secondary)
    }
}

/// A small rounded label, e.g. the cache type of a response.
struct DemoBadge: View {
    private let text: String
    private let color: Color

    init(_ text: String, color: Color = .accentColor) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
            .foregroundStyle(color)
    }
}

/// A placeholder shown while an image is loading.
struct DemoPlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemBackground))
            .overlay(ProgressView())
    }
}

/// A view shown when an image fails to load.
struct DemoFailureView: View {
    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemBackground))
            .overlay {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
    }
}

/// Pads a figure out to a fixed number of characters, so that a value sampled
/// ten times a second doesn't shift the text around it.
func demoPad(_ text: String, to width: Int) -> String {
    text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
}

func demoByteCount(_ count: Int64) -> String {
    // `ByteCountFormatter` writes "Zero KB", which reads like a fault in a
    // column of figures that are otherwise moving.
    guard count > 0 else { return "0 KB" }
    return ByteCountFormatter.string(fromByteCount: count, countStyle: .binary)
}

func demoByteCount(_ count: Int) -> String {
    demoByteCount(Int64(count))
}

/// Embeds a `UIViewController` in SwiftUI. The demo uses it to show the
/// UIKit screens in the same navigation stack as the SwiftUI ones.
struct ViewControllerView<ViewController: UIViewController>: UIViewControllerRepresentable {
    private let make: () -> ViewController

    init(_ make: @escaping () -> ViewController) {
        self.make = make
    }

    func makeUIViewController(context: Context) -> ViewController {
        make()
    }

    func updateUIViewController(_ viewController: ViewController, context: Context) {
        // Do nothing
    }
}

/// A square cell for a grid. The content is clipped to the cell bounds, which
/// a plain `aspectRatio(_:contentMode: .fill)` on the image would not do.
struct SquareCell<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { content }
            .clipShape(Rectangle())
    }
}

// MARK: - Stage and Console

extension View {
    /// Lays a demo screen out as a stage and a console: the view stays put and
    /// the diagnostics live in an inspector beside it – a column where there is
    /// room for one, a sheet below it where there isn't.
    ///
    /// Apply it last. Everything before it – the title, its menu, a toolbar item
    /// of the screen's own – is scoped to the stage; after it they drift into
    /// the console's column.
    ///
    /// - parameter collapsedHeight: How tall the console stands when it is a
    /// sheet at rest.
    func demoConsole<Console: View>(
        collapsedHeight: CGFloat,
        info: DemoInfo,
        @ViewBuilder console: @escaping () -> Console
    ) -> some View {
        modifier(DemoConsoleModifier(collapsedHeight: collapsedHeight, info: info, console: console))
    }
}

private struct DemoConsoleModifier<Console: View>: ViewModifier {
    let collapsedHeight: CGFloat
    let info: DemoInfo
    @ViewBuilder let console: () -> Console

    @State private var detent: PresentationDetent
    /// Whether the console is on screen. It starts closed and is asked for once
    /// the screen is up: a sheet asked for in the same update that pushes the
    /// screen is dropped rather than queued, and never retried.
    ///
    /// State, and not a constant: `inspector` writes `false` here when its sheet
    /// goes away, and a constant swallows the write.
    @State private var isShowingConsole = false
    @State private var isShowingInfo = false
    /// The screen a row of the console asked for, pushed once the console
    /// sheet has gone: pushed under it, the next screen would sit beneath this
    /// console, and its own console would be dropped.
    @State private var pendingRoute: DemoRoute?
    /// Whether the screen has been on display before, which makes this
    /// appearance a return from a screen pushed over it.
    @State private var hasAppeared = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.demoOpen) private var open

    init(collapsedHeight: CGFloat, info: DemoInfo, @ViewBuilder console: @escaping () -> Console) {
        self.collapsedHeight = collapsedHeight
        self.info = info
        self.console = console
        _detent = State(initialValue: .height(collapsedHeight))
    }

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .padding(.horizontal, 16)
                .padding(.top, 12)
                // A sheet covers the bottom edge; a column leaves it to the stage.
                .padding(.bottom, isConsoleSheet ? 0 : 16)
                .frame(height: stageHeight(in: proxy), alignment: .top)
                .animation(.snappy, value: detent)
        }
        .background(Color(.systemGroupedBackground))
        .demoInfoButton(isPresented: $isShowingInfo)
        // A turn of the loop after the screen arrives – see `isShowingConsole`.
        .task {
            if hasAppeared {
                // Back from a screen a row of the console pushed. Asked for
                // while the pop is still animating, the sheet presents empty
                // and stays that way.
                guard (try? await Task.sleep(for: .milliseconds(600))) != nil else { return }
            } else {
                await Task.yield()
                hasAppeared = true
            }
            isShowingConsole = true
        }
        .inspector(isPresented: $isShowingConsole) {
            console()
                .listStyle(.insetGrouped)
                // Where the sheet begins, for the pipeline HUD to stay above.
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { minY in
                    DemoHUD.shared.consoleSheetMinY = isConsoleSheet ? minY : nil
                }
                .onDisappear {
                    DemoHUD.shared.consoleSheetMinY = nil
                    if let pendingRoute {
                        self.pendingRoute = nil
                        open?(pendingRoute)
                    }
                }
                .environment(\.demoOpenFromConsole, DemoOpenAction { route in
                    guard isConsoleSheet else {
                        open?(route)
                        return
                    }
                    // Back on this screen, the console comes up again with
                    // the screen, as it did the first time.
                    pendingRoute = route
                    isShowingConsole = false
                })
                .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
                .presentationDetents([collapsedDetent, .medium, .large], selection: $detent)
                .presentationDragIndicator(.visible)
                // Keeps the stage behind the sheet interactive, so the
                // animation plays on while the settings change.
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled()
                // The console covers the sheet the toolbar button would present,
                // so the explanation is presented from inside the inspector.
                .sheet(isPresented: $isShowingInfo) {
                    DemoInfoSheet(info: info)
                }
        }
    }

    private var collapsedDetent: PresentationDetent { .height(collapsedHeight) }

    /// Whether the console is a sheet below the stage rather than a column
    /// beside it.
    private var isConsoleSheet: Bool {
        horizontalSizeClass == .compact
    }

    /// The room the console leaves for the stage. Beside the stage, all of it;
    /// below it, the console is presented over the screen rather than next to
    /// it, so the stage has to keep clear of it by hand.
    private func stageHeight(in proxy: GeometryProxy) -> CGFloat {
        guard isConsoleSheet else {
            return proxy.size.height
        }
        let console = detent == collapsedDetent
            ? collapsedHeight
            // Everything above `.medium` covers the stage anyway.
            : proxy.size.height / 2
        return max(200, proxy.size.height - console)
    }
}
