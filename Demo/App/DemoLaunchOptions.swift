// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import OSLog
import SwiftUI

/// What the app was launched with: the arguments that open it in a known state,
/// so that a screenshot script gets to a screen without tapping its way there.
///
/// An argument written as `-name value` lands in the argument domain of
/// `UserDefaults`, which is where they are read from, so the same names work
/// from `xcrun simctl launch`, from Edit Scheme › Run › Arguments Passed On
/// Launch, and from `defaults write`. They are read once, at launch: a default
/// changed while the app runs changes nothing.
///
/// Adding an argument is a case in ``Argument``, which the **Automation** screen
/// lists, and a property here that reads it.
struct DemoLaunchOptions {
    /// `-demoScreen <id>`: the screen the app opens on. `nil` opens the
    /// catalog, and so does an id that no screen has.
    private(set) var route: DemoRoute?

    /// `-demoLab 0` leaves the Lab row out of the catalog, for a screenshot of
    /// the catalog alone. Only the row: `-demoScreen` still opens the Lab.
    private(set) var showsLab = true

    /// `-demoHUD 1` opens the app with the pipeline HUD over every screen,
    /// folded into its pill; `-demoHUD expanded` opens it as the panel.
    private(set) var showsHUD = false
    private(set) var expandsHUD = false

    /// `-demoFixtures offline` starts the app with every image served by
    /// fixtures – see ``DemoFixtureMode``. `-demoDeterministic 1` implies it,
    /// unless `-demoFixtures network` says otherwise.
    private(set) var isOffline = false

    /// `-demoDeterministic 1` starts the app the same way every time, for a
    /// screenshot script: offline, with the disk caches emptied, no fade on
    /// UIKit image views, and counted tokens where a screen would draw random
    /// ones. What still varies: timings, the frames of animations, and the
    /// figures of the HUD.
    private(set) var isDeterministic = false

    /// `-demoNetwork <preset>` starts the app with the network conditions of
    /// a preset on – see ``DemoNetworkConditions``. `nil`, the default, starts
    /// it on the network as it is, and so does `off` or a preset that doesn't
    /// exist.
    private(set) var networkPreset: DemoNetworkConditions.Preset?

    /// `-demoAutorun 1` starts the run of a screen that has one as soon as
    /// the screen opens, once per launch: Decompression scrolls in each of its
    /// configurations, Concurrency Inspector starts a burst, Scroll Stress
    /// scrolls, Cancellation Torture and Cache Torture run their checks,
    /// Memory Soak runs for a minute, Animation Lab starts its soak. A script
    /// can then take a screenshot of the results without a tap.
    private(set) var autoruns = false

    /// What each argument was set to, as written, for the **Automation** screen
    /// to report. An argument that wasn't passed isn't in it.
    private(set) var values: [Argument: String] = [:]

    /// The options of this launch.
    static let current = DemoLaunchOptions(defaults: .standard)

    init(defaults: UserDefaults) {
        for argument in Argument.allCases {
            values[argument] = defaults.string(forKey: argument.rawValue)
        }
        if let id = values[.screen] {
            route = DemoRoute(id: id)
            if route == nil {
                Self.logger.error("-demoScreen \(id, privacy: .public): no screen has this id, so the app opens on the catalog. The Automation screen in the Lab lists the ids.")
            }
        }
        if values[.lab] != nil {
            showsLab = defaults.bool(forKey: Argument.lab.rawValue)
        }
        if let value = values[.hud] {
            expandsHUD = value == "expanded"
            showsHUD = expandsHUD || defaults.bool(forKey: Argument.hud.rawValue)
        }
        if values[.deterministic] != nil {
            isDeterministic = defaults.bool(forKey: Argument.deterministic.rawValue)
        }
        isOffline = isDeterministic
        if let value = values[.fixtures] {
            switch value {
            case "offline": isOffline = true
            case "network": isOffline = false
            default:
                let fallback = isOffline ? "offline" : "online"
                Self.logger.error("-demoFixtures \(value, privacy: .public): not a mode, so the app starts \(fallback, privacy: .public). The modes are offline and network.")
            }
        }
        if values[.autorun] != nil {
            autoruns = defaults.bool(forKey: Argument.autorun.rawValue)
        }
        if let value = values[.network], value != "off" {
            networkPreset = DemoNetworkConditions.Preset(rawValue: value)
            if networkPreset == nil {
                Self.logger.error("-demoNetwork \(value, privacy: .public): not a preset, so the app starts with the network conditions off. The values are \(Argument.network.values, privacy: .public).")
            }
        }
    }

    private static let logger = Logger(subsystem: "com.github.kean.NukeDemo", category: "Launch")
}

extension DemoLaunchOptions {
    /// Whether `screen` starts its run on its own now: with `-demoAutorun 1`,
    /// the first time the screen asks in a launch, not each time it comes
    /// back.
    @MainActor
    static func claimAutorun(for screen: DemoScreen) -> Bool {
        guard current.autoruns else { return false }
        return autorunScreens.insert(screen).inserted
    }

    @MainActor private static var autorunScreens: Set<DemoScreen> = []
}

extension DemoLaunchOptions {
    /// A launch argument, in the order the **Automation** screen lists them.
    ///
    /// The raw value is the argument's key in `UserDefaults`: its name without
    /// the dash.
    enum Argument: String, CaseIterable, Identifiable {
        case screen = "demoScreen"
        case lab = "demoLab"
        case hud = "demoHUD"
        case fixtures = "demoFixtures"
        case deterministic = "demoDeterministic"
        case network = "demoNetwork"
        case autorun = "demoAutorun"

        var id: String { rawValue }

        /// The argument as it is written on a command line.
        var name: String { "-" + rawValue }

        /// The values it takes.
        var values: String {
            switch self {
            case .screen: "<id>"
            case .lab: "0 | 1"
            case .hud: "0 | 1 | expanded"
            case .fixtures: "offline | network"
            case .deterministic: "0 | 1"
            case .network: (["off"] + DemoNetworkConditions.Preset.allCases.map(\.rawValue)).joined(separator: " | ")
            case .autorun: "0 | 1"
            }
        }

        /// What it does, and what the app does without it.
        var summary: LocalizedStringKey {
            switch self {
            case .screen: "Opens the app on a screen, with the menus it is reached through beneath it; `lab` opens the Lab menu. An id that no screen has opens the catalog, and Console says why."
            case .lab: "`0` leaves the Lab row out of the catalog, for a screenshot of the catalog alone. `1`, the default, keeps it."
            case .hud: "`1` opens the app with the pipeline HUD over every screen, folded into its pill, and `expanded` with its panel open. `0`, the default, leaves it off until the gauge in the navigation bar switches it on."
            case .fixtures: "`offline` serves every image from fixtures – generated or bundled stand-ins for the demo's URLs – and sends nothing to the network. `network`, the default, loads the catalog over the network; Lab screens start on fixtures either way. Fixture Mode in the Lab switches it while the app runs."
            case .deterministic: "`1` starts the app the same way every time: offline unless `-demoFixtures network` says otherwise, with the disk caches emptied, no fade on UIKit image views, and counted tokens instead of random ones. Timings, animation frames, and the HUD's figures still vary."
            case .network: "Starts the app with the network conditions of a preset on, so every download of every pipeline is slowed, lost, failed, or cut off the way the preset says. `off`, the default, leaves the network as it is. Network Conditions in the Lab switches them while the app runs."
            case .autorun: "`1` starts the run of a screen that has one as soon as it opens, once per launch: Decompression scrolls its grid in each of four configurations, in about 30 s, Concurrency Inspector starts a burst of 240 requests, Scroll Stress scrolls for 10 s, Cancellation Torture runs its checks and the slot check, in about 15 s, Memory Soak runs for a minute, Cache Torture runs its checks, in about 12 s, and Animation Lab starts its hour-long soak. `0`, the default, waits for a tap."
            }
        }
    }
}
