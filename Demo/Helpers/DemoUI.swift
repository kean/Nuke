// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// A short paragraph explaining what the screen demonstrates.
struct DemoIntro: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
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
