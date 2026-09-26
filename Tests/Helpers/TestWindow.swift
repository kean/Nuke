// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

#if !os(watchOS)

import CoreGraphics

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A window on screen for as long as the test keeps it, which puts views in
/// it the way an app does: what starts an animation or resumes a video.
@MainActor
final class TestWindow {
    /// The frame of the window, and of every view added to it.
    let frame = CGRect(x: 0, y: 0, width: 100, height: 100)

#if os(macOS)
    private let window: NSWindow

    /// Shows a window, with the given view in it.
    init(view: NSView? = nil) {
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        if let view {
            add(view)
        }
        window.orderFront(nil)
    }

    /// Adds the view to the window, filling it.
    func add(_ view: NSView) {
        view.frame = frame
        window.contentView?.addSubview(view)
    }

    func close() {
        window.orderOut(nil)
    }
#else
    private let window: UIWindow

    /// Shows a window, with the given view in it.
    init(view: UIView? = nil) {
        window = UIWindow(frame: frame)
        if let view {
            add(view)
        }
        window.isHidden = false
    }

    /// Adds the view to the window, filling it.
    func add(_ view: UIView) {
        view.frame = frame // A view in a window has a size, as the AppKit half does
        window.addSubview(view)
    }

    func close() {
        window.isHidden = true
    }
#endif
}

#endif
