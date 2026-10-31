// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

import Accessibility

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Tracks the two settings that ask for animations not to start on their own:
/// Accessibility › Motion › Auto-Play Animated Images, and Reduce Motion.
///
/// Every ``AnimatedImageView`` follows it, so `LazyImageView`, `ImageLoader`,
/// and `AnimatedImage` all answer to the same two settings. The values are read
/// once and kept up to date by the notifications, which leaves a view with a
/// property to read.
@MainActor
final class AnimatedImageAutoPlaySettings {
    /// The settings every view follows.
    static let shared = AnimatedImageAutoPlaySettings()

    /// Accessibility › Motion › Auto-Play Animated Images. There is no such
    /// setting before iOS 17, macOS 14, and tvOS 17, so it reads `true` there.
    private(set) var isAutoPlayEnabled: Bool

    /// Accessibility › Motion › Reduce Motion.
    private(set) var isReduceMotionEnabled: Bool

    /// `true` while an animation may start on its own.
    ///
    /// Reduce Motion counts even with Auto-Play on: an animation that starts by
    /// itself is the motion that setting asks to keep off the screen.
    var allowsPlayback: Bool { isAutoPlayEnabled && !isReduceMotionEnabled }

    /// A hash table rather than the array `AnimatedImagePowerMonitor` keeps,
    /// which looks through every observer to add one. Adding a view is the only
    /// thing done per view, and a list goes through a lot of them. Weak: the
    /// views hold the settings, not the other way around.
    private let views = NSHashTable<AnimatedImageView>.weakObjects()

    /// Creates settings that follow the system.
    init() {
        self.isAutoPlayEnabled = Self.isSystemAutoPlayEnabled
        self.isReduceMotionEnabled = Self.isSystemReduceMotionEnabled
        let update: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFromSystem() }
        }
        // They arrive on whatever thread the system posts them on, so they are
        // delivered back to the main queue.
        if #available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, *) {
            NotificationCenter.default.addObserver(forName: AccessibilitySettings.animatedImagesEnabledDidChangeNotification, object: nil, queue: .main, using: update)
        } else if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            NotificationCenter.default.addObserver(forName: .AXAnimatedImagesEnabledDidChange, object: nil, queue: .main, using: update)
        }
#if os(macOS)
        // Not the default center: this one is only posted to the workspace's.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main, using: update)
#else
        NotificationCenter.default.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main, using: update)
#endif
    }

    /// Creates settings that don't follow the system: the values are the ones
    /// it is given, and the ones ``update(isAutoPlayEnabled:isReduceMotionEnabled:)``
    /// gives it after that.
    ///
    /// The tests use it, because nothing lets them change the system's.
    init(isAutoPlayEnabled: Bool, isReduceMotionEnabled: Bool) {
        self.isAutoPlayEnabled = isAutoPlayEnabled
        self.isReduceMotionEnabled = isReduceMotionEnabled
    }

    /// Registers a view to be told when the answer changes.
    func add(_ view: AnimatedImageView) {
        views.add(view)
    }

    /// Changes the settings and tells the views about it.
    func update(isAutoPlayEnabled: Bool, isReduceMotionEnabled: Bool) {
        let allowedPlayback = allowsPlayback
        self.isAutoPlayEnabled = isAutoPlayEnabled
        self.isReduceMotionEnabled = isReduceMotionEnabled
        guard allowsPlayback != allowedPlayback else { return }
        for view in views.allObjects {
            view.updatePlaybackState()
        }
    }

    private func updateFromSystem() {
        update(isAutoPlayEnabled: Self.isSystemAutoPlayEnabled, isReduceMotionEnabled: Self.isSystemReduceMotionEnabled)
    }

    private static var isSystemAutoPlayEnabled: Bool {
        if #available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, *) {
            return AccessibilitySettings.animatedImagesEnabled
        }
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            return AXAnimatedImagesEnabled()
        }
        return true
    }

    private static var isSystemReduceMotionEnabled: Bool {
#if os(macOS)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
#else
        UIAccessibility.isReduceMotionEnabled
#endif
    }
}

#endif
