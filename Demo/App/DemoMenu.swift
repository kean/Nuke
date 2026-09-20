// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// The demo catalog: the screens for adopting Nuke, in the order an app tends
/// to need them rather than the order of the documentation, and the Lab last.
///
/// The rows come from ``DemoScreen``, and every one of them pushes a
/// ``DemoScreen`` rather than a view.
///
/// On a phone the logo is in the navigation bar, which also gives the rows a
/// bar to scroll under. On an iPad it stands large beside the catalog, and the
/// catalog has no bar.
struct DemoMenu: View {
    /// Starts out holding the screen the app was launched on, if it was
    /// launched on one – see ``DemoLaunchOptions``.
    @State private var path: [DemoScreen] = DemoLaunchOptions.current.screen.map { [$0] } ?? []
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let showsLab = DemoLaunchOptions.current.showsLab

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if horizontalSizeClass == .regular {
                    HStack(spacing: 0) {
                        DemoLogo()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                            .ignoresSafeArea()
                        menu
                            .frame(maxWidth: .infinity)
                    }
                    .background(Color(.systemGroupedBackground).ignoresSafeArea())
                    .toolbar(.hidden, for: .navigationBar)
                } else {
                    menu
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                DemoWordmark()
                            }
                        }
                }
            }
            // The title is what the back button of the next screen reads.
            .navigationTitle("Nuke")
            .navigationBarTitleDisplayMode(.inline)
        }
        // Over the whole stack, so it stays put as screens come and go.
        .demoPipelineHUD()
        // For the rows that can't be a `NavigationLink` – see `DemoLink` – and
        // for the HUD, which stands outside the stack. Outside the overlay:
        // an environment set under it wouldn't reach the HUD.
        .environment(\.demoOpen, DemoOpenAction { screen in
            guard path.last != screen else { return }
            path.append(screen)
        })
    }

    private var menu: some View {
        @Bindable var hud = DemoHUD.shared
        return List {
            let sections = DemoScreen.CatalogSection.allCases.filter { showsLab || $0 != .lab }
            ForEach(sections, id: \.self) { section in
                Section {
                    ForEach(section.screens) { screen in
                        DemoLink(screen)
                    }
                    if section == .lab {
                        // The one switch of the HUD: it is on from launch, and
                        // its own menu opens the two instruments.
                        Toggle(isOn: $hud.isVisible) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pipeline HUD")
                                Text("Every pipeline's figures, over any screen")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(section.title)
                } footer: {
                    if section == sections.last {
                        VStack(alignment: .leading, spacing: 24) {
                            Text(section.footer)
                            Text("Nuke Demo · Documentation: kean-docs.github.io/nuke")
                        }
                    } else {
                        Text(section.footer)
                    }
                }
            }
        }
        .demoHUDRoom()
        .demoDestinations()
    }
}

/// The Nuke logo beside its tagline, the way the README opens, in the
/// navigation bar of the catalog on a phone.
private struct DemoWordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            Image("NukeLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 24)
            Text("Image Loading System")
                .font(.headline)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nuke, Image Loading System")
        .accessibilityAddTraits(.isHeader)
    }
}

/// The Nuke logo over its tagline, beside the catalog on an iPad.
private struct DemoLogo: View {
    var body: some View {
        VStack(spacing: 24) {
            Image("NukeLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            Text("Image Loading System")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nuke, Image Loading System")
        .accessibilityAddTraits(.isHeader)
    }
}

/// A catalog row that pushes a screen: the title over a caption.
///
/// Inside a console it is a button that asks the console to push the screen:
/// a console presented as a sheet has no navigation stack of its own, so a
/// `NavigationLink` there does nothing.
struct DemoLink: View {
    private let screen: DemoScreen

    @Environment(\.demoOpenFromConsole) private var openFromConsole

    init(_ screen: DemoScreen) {
        self.screen = screen
    }

    var body: some View {
        if let openFromConsole {
            Button {
                openFromConsole(screen)
            } label: {
                HStack {
                    label
                    Spacer(minLength: 8)
                    // The one a `NavigationLink` in a list draws.
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
        } else {
            NavigationLink(value: screen) {
                label
            }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(screen.title)
            Text(screen.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Pushes a screen onto the demo's navigation stack.
struct DemoOpenAction {
    let open: @MainActor (DemoScreen) -> Void

    @MainActor
    func callAsFunction(_ screen: DemoScreen) {
        open(screen)
    }
}

extension EnvironmentValues {
    /// Pushes a screen onto the navigation stack of the catalog, for a row
    /// that can't be a `NavigationLink`.
    @Entry var demoOpen: DemoOpenAction?

    /// Set inside a console: closes the console, if it is a sheet, then
    /// pushes the screen. ``DemoLink`` uses it.
    @Entry var demoOpenFromConsole: DemoOpenAction?
}

#Preview {
    DemoMenu()
}
