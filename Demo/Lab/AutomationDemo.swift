// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// The launch arguments the app understands and the id of every screen, each
/// with the `simctl launch` line that opens the app on it: what a screenshot
/// script is written from.
///
/// Built from ``DemoLaunchOptions/Argument`` and ``DemoScreen``, so an argument
/// or a screen is listed here as soon as it exists.
struct AutomationDemo: View {
    private let options = DemoLaunchOptions.current

    var body: some View {
        List {
            arguments
            ForEach(DemoScreen.CatalogSection.allCases.filter { !$0.screens.isEmpty }, id: \.self) { section in
                Section(section.title) {
                    ForEach(section.screens) { screen in
                        RouteRow(.screen(screen), title: screen.title)
                    }
                }
            }
            Section("Lab") {
                RouteRow(.lab, title: "Lab")
            }
            ForEach(DemoScreen.LabGroup.allCases.filter { !$0.screens.isEmpty }, id: \.self) { group in
                Section("Lab › \(group.title)") {
                    ForEach(group.screens) { screen in
                        RouteRow(.screen(screen), title: screen.title)
                    }
                }
            }
        }
        .demoInfo(Self.info)
    }

    private var arguments: some View {
        Section {
            ForEach(DemoLaunchOptions.Argument.allCases) { argument in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: "\(argument.name) \(argument.values)")
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        if let value = options.values[argument] {
                            DemoMonoLabel(value, tint: .accentColor)
                        }
                    }
                    Text(argument.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .textSelection(.enabled)
            }
        } header: {
            Text("Arguments")
        } footer: {
            Text("Pass them after the bundle id, or add them under Edit Scheme › Run › Arguments Passed On Launch. On the right, what this launch was given.")
        }
    }

    private static let info = DemoInfo(
        "Automation",
        "Launch arguments open the app in a known state, so a script can take a screenshot of any screen without tapping its way there. A title can change; an id can't.",
        code: """
        xcrun simctl launch booted com.github.kean.NukeDemo \\
            -demoScreen caching -demoLab 0
        """,
        points: [
            .init("From Xcode", "The same names work under Edit Scheme › Run › Arguments Passed On Launch. Launch arguments land in `UserDefaults`, which is where the app reads them, once, at launch."),
            .init("Unknown ids", "An id that no screen has opens the catalog, and Console says why under the `com.github.kean.NukeDemo` subsystem.")
        ]
    )
}

/// A screen, its id, and the command that opens the app on it.
private struct RouteRow: View {
    private let route: DemoRoute
    private let title: String

    init(_ route: DemoRoute, title: String) {
        self.route = route
        self.title = title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The id beside the title where there is room for both, under it
            // where there isn't.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                    Spacer(minLength: 16)
                    DemoMonoLabel(route.id)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    DemoMonoLabel(route.id)
                }
            }
            // On one line, scrolled rather than wrapped: a wrapped command
            // breaks the id at its hyphens.
            ScrollView(.horizontal) {
                Text(verbatim: "xcrun simctl launch booted \(Self.bundleID) \(DemoLaunchOptions.Argument.screen.name) \(route.id)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .textSelection(.enabled)
    }

    private static let bundleID = Bundle.main.bundleIdentifier ?? "com.github.kean.NukeDemo"
}
