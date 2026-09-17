// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// The Lab: instruments and torture rigs for working on Nuke, where the catalog
/// is for adopting it.
///
/// A Lab screen may cripple the pipeline to make a point – disable its caches,
/// push its budgets past sensible values – and it reports numbers rather than
/// explaining an API: the catalog screen for that API does the explaining. The
/// groups come from ``DemoScreen``, and one with no screens yet is left out.
struct LabMenu: View {
    var body: some View {
        List {
            ForEach(groups, id: \.self) { group in
                Section {
                    ForEach(group.screens) { screen in
                        DemoLink(screen, status: Self.status(of: screen))
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    // Under the last group, whichever that is.
                    if group == groups.last {
                        Text("Instruments and torture rigs for whoever works on Nuke. Caches are turned off where they would hide the work, and the screens report numbers rather than explain them – the catalog does that.")
                    }
                }
            }
        }
        .navigationTitle("Lab")
    }

    private var groups: [DemoScreen.LabGroup] {
        DemoScreen.LabGroup.allCases.filter { !$0.screens.isEmpty }
    }

    /// What a switch in the Rig is set to while it changes what every screen
    /// shows, or `nil` while it doesn't.
    @MainActor
    private static func status(of screen: DemoScreen) -> Text? {
        let status: String? = switch screen {
        case .fixtureMode: DemoFixtureMode.shared.isOffline ? "Offline" : nil
        case .networkConditions: DemoNetworkConditions.shared.badge
        default: nil
        }
        return status.map { Text($0).foregroundStyle(.orange) }
    }

    /// The switches of the Rig that are on, for the row into the Lab: why the
    /// images of a catalog screen are fixtures, or fail, or crawl.
    @MainActor
    static var rigStatus: Text? {
        let switches = [
            DemoFixtureMode.shared.isOffline ? "Offline" : nil,
            DemoNetworkConditions.shared.badge
        ].compactMap { $0 }
        guard !switches.isEmpty else {
            return nil
        }
        return Text(switches.joined(separator: " · ")).foregroundStyle(.orange)
    }
}

#Preview {
    NavigationStack {
        LabMenu()
            .demoDestinations()
    }
}
