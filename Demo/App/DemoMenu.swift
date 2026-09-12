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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
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
            lab
        }
        .demoDestinations()
    }

    /// The sections of the catalog that have screens in them.
    private var catalog: some View {
        ForEach(DemoScreen.CatalogSection.allCases.filter { !$0.screens.isEmpty }, id: \.self) { section in
            Section {
                ForEach(section.screens) { screen in
                    DemoLink(screen)
                }
            } header: {
                Text(section.title)
            } footer: {
                Text(section.footer)
            }
        }
    }

    /// A single row, last, where it stays out of the way of someone adopting
    /// Nuke.
    private var lab: some View {
        Section {
            DemoLink(.lab, title: "Lab", subtitle: "Instruments and stress rigs for working on Nuke")
        } footer: {
            Text("Nuke Demo · Documentation: kean-docs.github.io/nuke")
        }
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
