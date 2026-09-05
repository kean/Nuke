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

/// Hosts a SwiftUI view in a window so that its lifecycle (`onAppear`,
/// `onDisappear`) and state updates are delivered the same way they are in an app.
///
/// The hosted content is rebuilt from `value`, which the test can change with
/// ``update(_:)`` to simulate the view being reconfigured by its parent.
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
        @Published var isContentInstalled = true

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

    /// Detaches the hosted view from the window, triggering `onDisappear`. The
    /// view keeps the state it owns, like a view that scrolls out of sight.
    func hideContent(until condition: () -> Bool = { false }) async {
#if os(macOS)
        window.contentView = NSView(frame: frame)
#else
        window.rootViewController = UIViewController()
#endif
        await render(until: condition)
    }

    /// Re-attaches the hosted view to the window, triggering `onAppear`.
    func showContent(until condition: () -> Bool = { false }) async {
#if os(macOS)
        window.contentView = hostingView
#else
        window.rootViewController = controller
#endif
        await render(until: condition)
    }

    /// Removes the content from the view hierarchy entirely, releasing the
    /// state that it owns.
    func removeContent(until condition: () -> Bool = { false }) async {
        model.isContentInstalled = false
        await render(until: condition)
    }

    /// The first view of the given type in the hosted hierarchy.
    ///
    /// The only way to see what SwiftUI did to a `UIViewRepresentable`'s view:
    /// the representable itself is not reachable from a test.
    func firstView<T: HostedView>(ofType type: T.Type) -> T? {
#if os(macOS)
        hostingView.firstDescendant(ofType: type)
#else
        controller.view.firstDescendant(ofType: type)
#endif
    }

    /// Gives SwiftUI a chance to apply pending state changes and lay out.
    ///
    /// Returns as soon as `condition` holds; otherwise pumps for a fixed number
    /// of turns. Some transitions (notably `onDisappear` on UIKit) are delivered
    /// over several run loop turns rather than synchronously.
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

#if os(macOS)
typealias HostedView = NSView
#else
typealias HostedView = UIView
#endif

extension HostedView {
    func firstDescendant<T: HostedView>(ofType type: T.Type) -> T? {
        if let match = self as? T { return match }
        for subview in subviews {
            if let match = subview.firstDescendant(ofType: type) { return match }
        }
        return nil
    }
}

private struct RootView<Value, Content: View>: View {
    @ObservedObject var model: ViewHost<Value, Content>.Model
    let content: (Value) -> Content

    var body: some View {
        ZStack {
            if model.isContentInstalled {
                content(model.value)
            }
        }
    }
}

#endif
