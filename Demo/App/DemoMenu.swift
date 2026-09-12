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
            DemoLink(.lab, title: "Lab", subtitle: "Instruments and stress rigs for working on Nuke")
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

/// A menu row that pushes a screen, or the Lab: the title over a caption.
struct DemoLink: View {
    private let route: DemoRoute
    private let title: String
    private let subtitle: String

    init(_ screen: DemoScreen) {
        self.init(.screen(screen), title: screen.title, subtitle: screen.subtitle)
    }

    init(_ route: DemoRoute, title: String, subtitle: String) {
        self.route = route
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    DemoMenu()
}
