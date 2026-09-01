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

    /// Adds the question mark button without the sheet.
    ///
    /// iOS presents one sheet per screen and drops the second, so a screen that
    /// keeps a sheet of its own on display has to present ``DemoInfoSheet``
    /// from inside that sheet. This is the button for it.
    func demoInfoButton(isPresented: Binding<Bool>) -> some View {
        toolbar {
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

func demoByteCount(_ count: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: count, countStyle: .binary)
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
