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
    private(set) var screen: DemoScreen?

    /// `-demoLab 0` leaves the Lab section out of the catalog, for a
    /// screenshot of the rest alone. Only the section: `-demoScreen` still
    /// opens a Lab screen.
    private(set) var showsLab = true

    /// The pipeline HUD stands over every screen, folded into its pill.
    /// `-demoHUD 0` takes it off, for a screenshot of a screen alone;
    /// `-demoHUD expanded` opens the card out.
    private(set) var showsHUD = true
    private(set) var expandsHUD = false

    /// `-demoHUDCorner <corner>`: the corner the HUD starts in, out of the way
    /// of whatever a screenshot is of. It is dragged between them by hand.
    private(set) var hudCorner = DemoHUD.Corner.bottomLeading

    /// `-demoAutorun 1` starts the run of a screen that has one as soon as
    /// the screen opens, once per launch, so that a script can take a
    /// screenshot of the results without a tap.
    private(set) var autoruns = false

    /// `-demoDetails 1` opens the **Pipeline Details** sheet a moment after
    /// launch, which is otherwise reached through the HUD's info button.
    private(set) var opensDetails = false

    /// The options of this launch.
    static let current = DemoLaunchOptions(defaults: .standard)

    init(defaults: UserDefaults) {
        if let id = defaults.string(forKey: "demoScreen") {
            screen = DemoScreen(rawValue: id)
            if screen == nil {
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
        if let value = defaults.string(forKey: "demoHUDCorner") {
            if let corner = DemoHUD.Corner(rawValue: value) {
                hudCorner = corner
            } else {
                Self.logger.error("-demoHUDCorner \(value, privacy: .public): the corners are \(DemoHUD.Corner.allCases.map(\.rawValue).joined(separator: ", "), privacy: .public).")
            }
        }
        autoruns = defaults.bool(forKey: "demoAutorun")
        opensDetails = defaults.bool(forKey: "demoDetails")
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

    /// Whether the **Pipeline Details** sheet opens itself now: with
    /// `-demoDetails 1`, the first time the HUD asks in a launch. The HUD is
    /// laid over the navigation stack once, but a scene that goes away and
    /// comes back asks again.
    @MainActor
    static func claimDetails() -> Bool {
        guard current.opensDetails, !hasOpenedDetails else { return false }
        hasOpenedDetails = true
        return true
    }

    @MainActor private static var hasOpenedDetails = false
}
