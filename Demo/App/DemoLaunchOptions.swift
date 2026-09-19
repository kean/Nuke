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
/// changed while the app runs changes nothing. `Demo/README.md` lists them.
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

    /// `-demoAutorun 1` starts the run of a screen that has one as soon as
    /// the screen opens, once per launch, so that a script can take a
    /// screenshot of the results without a tap.
    private(set) var autoruns = false

    /// The options of this launch.
    static let current = DemoLaunchOptions(defaults: .standard)

    init(defaults: UserDefaults) {
        if let id = defaults.string(forKey: "demoScreen") {
            route = DemoRoute(id: id)
            if route == nil {
                Self.logger.error("-demoScreen \(id, privacy: .public): no screen has this id, so the app opens on the catalog. Demo/README.md lists the ids.")
            }
        }
        if defaults.object(forKey: "demoLab") != nil {
            showsLab = defaults.bool(forKey: "demoLab")
        }
        if let value = defaults.string(forKey: "demoHUD") {
            expandsHUD = value == "expanded"
            showsHUD = expandsHUD || defaults.bool(forKey: "demoHUD")
        }
        autoruns = defaults.bool(forKey: "demoAutorun")
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
