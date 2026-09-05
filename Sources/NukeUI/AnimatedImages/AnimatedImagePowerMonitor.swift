// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Tracks whether the system is asking for less work than usual: Low Power
/// Mode is on, or the device is hot enough to be throttling itself.
///
/// A player slows its clock down while this is true. It is what WebKit does
/// for the same two reasons – `LowPowerMode` and `ThermalMitigation` are two
/// of its throttling reasons, and each of them halves the rate its animations
/// run at.
@MainActor
final class AnimatedImagePowerMonitor {
    /// The monitor every player follows.
    static let shared = AnimatedImagePowerMonitor()

    /// `true` while the system is asking for less work.
    private(set) var isThrottling: Bool

    /// Weak: a player holds no reference to the monitor it registered with,
    /// and a monitor must not keep a player that went away alive.
    private struct Observer {
        weak var player: AnimatedImagePlayer?
    }

    private var observers: [Observer] = []

    /// Creates a monitor that follows the system.
    init() {
        self.isThrottling = AnimatedImagePowerMonitor.isSystemThrottling
        // Both notifications arrive on whatever thread the system posts them
        // on, so they are delivered back to the main queue.
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.setThrottling(AnimatedImagePowerMonitor.isSystemThrottling)
                }
            }
        }
    }

    /// Creates a monitor that doesn't follow the system: the state is the one
    /// it is given, and the one ``setThrottling(_:)`` gives it after that.
    ///
    /// The tests use it – nothing can put a device in Low Power Mode on their
    /// behalf, and a machine that happens to be in it must not change what
    /// they assert.
    init(isThrottling: Bool) {
        self.isThrottling = isThrottling
    }

    /// Registers a player to be told when the state changes.
    func add(_ player: AnimatedImagePlayer) {
        observers.removeAll { $0.player == nil }
        observers.append(Observer(player: player))
    }

    /// Changes the state and tells the players about it.
    func setThrottling(_ isThrottling: Bool) {
        guard isThrottling != self.isThrottling else { return }
        self.isThrottling = isThrottling
        observers.removeAll { $0.player == nil }
        for observer in observers {
            observer.player?.updateClockRate()
        }
    }

    private static var isSystemThrottling: Bool {
        let processInfo = ProcessInfo.processInfo
        if processInfo.isLowPowerModeEnabled {
            return true
        }
        // `.fair` is a device that is merely warm and is asked for nothing;
        // from `.serious` on, the system is already slowing the CPU and GPU
        // down and an animation has no business spending the rest.
        switch processInfo.thermalState {
        case .serious, .critical: return true
        default: return false
        }
    }
}
