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
    }

    private static let logger = Logger(subsystem: "com.github.kean.NukeDemo", category: "Launch")
}

extension DemoLaunchOptions {
    /// A launch argument, in the order the **Automation** screen lists them.
    ///
    /// The raw value is the argument's key in `UserDefaults`: its name without
    /// the dash.
    enum Argument: String, CaseIterable, Identifiable {
        case screen = "demoScreen"
        case lab = "demoLab"

        var id: String { rawValue }

        /// The argument as it is written on a command line.
        var name: String { "-" + rawValue }

        /// The values it takes.
        var values: String {
            switch self {
            case .screen: "<id>"
            case .lab: "0 | 1"
            }
        }

        /// What it does, and what the app does without it.
        var summary: LocalizedStringKey {
            switch self {
            case .screen: "Opens the app on a screen, with the menus it is reached through beneath it; `lab` opens the Lab menu. An id that no screen has opens the catalog, and Console says why."
            case .lab: "`0` leaves the Lab row out of the catalog, for a screenshot of the catalog alone. `1`, the default, keeps it."
            }
        }
    }
}
