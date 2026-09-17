// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// The demo catalog: the screens for adopting Nuke, in the order an app tends
/// to need them rather than the order of the documentation, and one row at the
/// bottom into the Lab.
///
/// The rows come from ``DemoScreen``, and every one of them pushes a
/// ``DemoRoute`` rather than a view.
struct DemoMenu: View {
    /// Starts out holding the screen the app was launched on, if it was
    /// launched on one – see ``DemoLaunchOptions``.
    @State private var path: [DemoRoute] = DemoLaunchOptions.current.route?.stack ?? []
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let showsLab = DemoLaunchOptions.current.showsLab

    var body: some View {
        NavigationStack(path: $path) {
            if horizontalSizeClass == .regular {
                // iPad: the logo takes the left pane, the catalog the right.
                HStack(spacing: 0) {
                    DemoLogoHeader(logoHeight: 96, taglineFont: .title2.weight(.bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    menu(showsLogo: false)
                        .frame(maxWidth: .infinity)
                }
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
            } else {
                // iPhone: the logo crowns the list, the way the README opens.
                menu(showsLogo: true)
            }
        }
        // For the rows that can't be a `NavigationLink` – see `DemoLink`.
        .environment(\.demoOpen, DemoOpenAction { path.append($0) })
        // Over the whole stack, so it stays put as screens come and go.
        .demoPipelineHUD()
    }

    private func menu(showsLogo: Bool) -> some View {
        List {
            if showsLogo {
                Section {
                    DemoLogoHeader(logoHeight: 56, taglineFont: .headline)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                }
                .listRowBackground(Color.clear)
            }
            catalog
            if showsLab {
                lab
            }
        }
        .demoHUDRoom()
        .demoDestinations()
    }

    /// The sections of the catalog that have screens in them.
    private var catalog: some View {
        let sections = DemoScreen.CatalogSection.allCases.filter { !$0.screens.isEmpty }
        return ForEach(sections, id: \.self) { section in
            Section {
                ForEach(section.screens) { screen in
                    DemoLink(screen)
                }
            } header: {
                Text(section.title)
            } footer: {
                if !showsLab, section == sections.last {
                    // With the Lab row left out, the page ends here.
                    VStack(alignment: .leading, spacing: 24) {
                        Text(section.footer)
                        pageFooter
                    }
                } else {
                    Text(section.footer)
                }
            }
        }
    }

    /// A single row, last, where it stays out of the way of someone adopting
    /// Nuke. `-demoLab 0` leaves it out.
    private var lab: some View {
        Section {
            DemoLink(.lab, title: "Lab", subtitle: "Instruments and stress rigs for working on Nuke", status: LabMenu.rigStatus)
        } footer: {
            pageFooter
        }
    }

    private var pageFooter: some View {
        Text("Nuke Demo · Documentation: kean-docs.github.io/nuke")
    }
}

/// The Nuke wordmark over its tagline, the way the README opens.
private struct DemoLogoHeader: View {
    let logoHeight: CGFloat
    let taglineFont: Font

    var body: some View {
        VStack(spacing: logoHeight / 4) {
            Image("NukeLogo")
                .resizable()
                .scaledToFit()
                .frame(height: logoHeight)
                .accessibilityLabel("Nuke")
            Text("Image Loading System")
                .font(taglineFont)
        }
    }
}

/// A menu row that pushes a screen, or the Lab: the title over a caption, and
/// a status at the end of the row, if any.
///
/// Inside a console it is a button that asks the console to push the screen:
/// a console presented as a sheet has no navigation stack of its own, so a
/// `NavigationLink` there does nothing.
struct DemoLink: View {
    private let route: DemoRoute
    private let title: String
    private let subtitle: String
    private let status: Text?

    @Environment(\.demoOpenFromConsole) private var openFromConsole

    init(_ screen: DemoScreen, status: Text? = nil) {
        self.init(.screen(screen), title: screen.title, subtitle: screen.subtitle, status: status)
    }

    init(_ route: DemoRoute, title: String, subtitle: String, status: Text? = nil) {
        self.route = route
        self.title = title
        self.subtitle = subtitle
        self.status = status
    }

    var body: some View {
        if let openFromConsole {
            Button {
                openFromConsole(route)
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
            NavigationLink(value: route) {
                label
            }
        }
    }

    private var label: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let status {
                // Inside the label, so it sits before the chevron: a badge
                // goes after it.
                Spacer(minLength: 8)
                status
                    .font(.subheadline)
            }
        }
    }
}

/// Pushes a route onto the demo's navigation stack.
struct DemoOpenAction {
    let open: @MainActor (DemoRoute) -> Void

    @MainActor
    func callAsFunction(_ route: DemoRoute) {
        open(route)
    }
}

extension EnvironmentValues {
    /// Pushes a route onto the navigation stack of the catalog, for a row
    /// that can't be a `NavigationLink`.
    @Entry var demoOpen: DemoOpenAction?

    /// Set inside a console: closes the console, if it is a sheet, then
    /// pushes the route. ``DemoLink`` uses it.
    @Entry var demoOpenFromConsole: DemoOpenAction?
}

#Preview {
    DemoMenu()
}
