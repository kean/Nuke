// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Observation
import os

/// The network every demo pipeline downloads through: the real one, or one
/// that is slow, loses requests, and breaks off in the middle on purpose.
///
/// A global switch rather than a screen to look at. While it is on, the probe
/// of every pipeline hands the pipeline a ``DemoConditionedDataLoader`` around
/// the loader it would have used – the configured one, or a fixture loader
/// offline – so every catalog screen shows what it does when the network
/// misbehaves, and no screen has to be written for it. The probe reads the
/// switch for every download, so a change applies to the next one, with no
/// pipeline rebuilt. Off, nothing is wrapped and nothing is drawn: a pipeline
/// downloads exactly as it does without the rig.
///
/// While it is on, the pipelines' own diagnostics (`ImageTask.Metrics`) have
/// no `URLSession` metrics, and a download `URLCache` answered reads as
/// `network` in them: the pipeline asks for those metrics by casting its
/// loader to `DataLoader`, and the rig isn't one. The probe's figures lose
/// nothing (see ``DemoConditionedDataLoader``).
///
/// `-demoNetwork <preset>` starts the app with a preset on. The **Network
/// Conditions** screen in the Lab switches it and sets each condition.
@MainActor @Observable
final class DemoNetworkConditions {
    static let shared = DemoNetworkConditions()

    /// Whether downloads go through the conditions.
    var isOn: Bool {
        didSet {
            guard isOn != oldValue else { return }
            publish()
            Self.logger.info("Network conditions \(self.isOn ? "on: \(self.title)" : "off", privacy: .public).")
        }
    }

    /// The conditions, which apply only while ``isOn``. A preset sets all of
    /// them.
    var profile: Profile {
        didSet {
            guard profile != oldValue else { return }
            publish()
        }
    }

    /// The preset the conditions match, or `nil` for a custom set.
    var preset: Preset? {
        Preset.allCases.first { $0.profile == profile }
    }

    /// The name of the conditions: the preset's, or "Custom".
    var title: String {
        preset?.title ?? "Custom"
    }

    /// What the HUD and the Lab rows show while the conditions are on, or
    /// `nil` while they are off.
    var badge: String? {
        isOn ? title : nil
    }

    private init() {
        let preset = DemoLaunchOptions.current.networkPreset
        isOn = preset != nil
        profile = (preset ?? .slow3G).profile
        publish()
    }

    private func publish() {
        let current = isOn ? profile : nil
        Self.state.withLock { $0 = current }
    }

    /// The conditions for a download that starts now, or `nil` while they are
    /// off: what the pipelines read, from any thread.
    nonisolated static var current: Profile? {
        state.withLock { $0 }
    }

    // Set at launch, before `shared` exists: a pipeline can start a download
    // before anything on the main actor reads the switch.
    private nonisolated static let state = OSAllocatedUnfairLock<Profile?>(initialState: DemoLaunchOptions.current.networkPreset?.profile)

    private nonisolated static let logger = Logger(subsystem: "com.github.kean.NukeDemo", category: "Network")
}

extension DemoNetworkConditions {
    /// What a download goes through.
    ///
    /// Each download waits ``latency``, give or take ``jitter``, before its
    /// loader starts. It is then drawn for each failure in turn – lost, a
    /// server error, cut off – so a download that is lost isn't also a server
    /// error, and a rate of 1 fails every download that got that far. Raising
    /// a rate only adds failures: a download is drawn the same numbers
    /// whatever the rates are.
    struct Profile: Hashable, Sendable {
        /// The wait before the loader starts: the round trip before the first
        /// byte.
        var latency: Duration = .zero
        /// How far the latency of a download strays from ``latency``, either
        /// way, at most.
        var jitter: Duration = .zero
        /// The bytes per second of the one link every conditioned download
        /// shares, or `nil` for as fast as the loader delivers them.
        var bandwidth: Int?
        /// The share of downloads that get no answer: they fail after their
        /// latency with `URLError(.timedOut)`, and the loader never starts.
        var lossRate: Double = 0
        /// The share of downloads a server fails: they fail after their
        /// latency with `DataLoader.Error.statusCodeUnacceptable(500)`, the
        /// error `DataLoader` fails a 500 with, before any data.
        var serverErrorRate: Double = 0
        /// The share of downloads cut off in the middle: the pipeline gets
        /// between a fifth and four fifths of the body, then
        /// `URLError(.networkConnectionLost)`.
        var truncationRate: Double = 0

        /// Whether any download can fail on purpose.
        var hasFailures: Bool {
            lossRate > 0 || serverErrorRate > 0 || truncationRate > 0
        }
    }

    /// Conditions with a name, for the switch on the screen and for
    /// `-demoNetwork`.
    enum Preset: String, CaseIterable, Identifiable, Sendable {
        case slow3G = "slow-3g"
        case lossy
        case flakyServer = "flaky-server"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .slow3G: "Slow 3G"
            case .lossy: "Lossy"
            case .flakyServer: "Flaky Server"
            }
        }

        var profile: Profile {
            switch self {
            case .slow3G:
                // Round the numbers browsers throttle to: 400 ms, 400 kbit/s.
                Profile(latency: .milliseconds(400), jitter: .milliseconds(100), bandwidth: 50 * 1024)
            case .lossy:
                Profile(latency: .milliseconds(150), jitter: .milliseconds(100), lossRate: 0.25)
            case .flakyServer:
                Profile(latency: .milliseconds(50), jitter: .milliseconds(25), serverErrorRate: 0.2, truncationRate: 0.2)
            }
        }
    }
}
