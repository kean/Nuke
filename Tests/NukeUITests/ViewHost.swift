// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

#if !os(watchOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Hosts a SwiftUI view in a window so that its lifecycle and state updates are
/// delivered the same way they are in an app.
///
/// The hosted content is rebuilt from `value`, which the test can change with
/// ``update(_:until:)`` to simulate the view being reconfigured by its parent.
@MainActor
final class ViewHost<Value, Content: View> {
    private let model: Model
    private let frame = CGRect(x: 0, y: 0, width: 200, height: 200)

#if os(macOS)
    private let hostingView: NSHostingView<RootView<Value, Content>>
    private let window: NSWindow
#else
    private let controller: UIHostingController<RootView<Value, Content>>
    private let window: UIWindow
#endif

    @MainActor
    final class Model: ObservableObject {
        @Published var value: Value

        init(value: Value) {
            self.value = value
        }
    }

    /// - parameters:
    ///   - value: The initial input for the hosted view.
    ///   - content: Builds the view under test. Called again whenever the value changes.
    init(_ value: Value, @ViewBuilder content: @escaping (Value) -> Content) {
        self.model = Model(value: value)
        let root = RootView(model: model, content: content)

#if os(macOS)
        self.hostingView = NSHostingView(rootView: root)
        self.hostingView.frame = frame
        self.window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        self.window.contentView = hostingView
        self.window.orderFront(nil)
#else
        self.controller = UIHostingController(rootView: root)
        self.controller.view.frame = frame
        self.window = UIWindow(frame: frame)
        self.window.rootViewController = controller
        self.window.isHidden = false
#endif
        layout()
    }

    /// Changes the input the content is built from, then lets SwiftUI render.
    func update(_ value: Value, until condition: () -> Bool = { false }) async {
        model.value = value
        await render(until: condition)
    }

    /// Gives SwiftUI a chance to apply pending state changes and lay out.
    ///
    /// Returns as soon as `condition` holds; otherwise pumps for a fixed number
    /// of turns.
    func render(until condition: () -> Bool = { false }) async {
        for _ in 0..<40 {
            layout()
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func layout() {
#if os(macOS)
        hostingView.layoutSubtreeIfNeeded()
#else
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
#endif
    }
}

private struct RootView<Value, Content: View>: View {
    @ObservedObject var model: ViewHost<Value, Content>.Model
    let content: (Value) -> Content

    var body: some View {
        ZStack {
            content(model.value)
        }
    }
}

#endif
