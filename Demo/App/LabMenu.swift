// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// The Lab: instruments and stress rigs for working on Nuke, where the catalog
/// is for adopting it.
///
/// A Lab screen may cripple the pipeline to make a point – disable its caches,
/// push its budgets past sensible values – and it reports numbers rather than
/// explaining an API: the catalog screen for that API does the explaining. The
/// screens come from ``DemoScreen``.
struct LabMenu: View {
    var body: some View {
        List {
            Section {
                ForEach(DemoScreen.lab) { screen in
                    DemoLink(screen)
                }
            } footer: {
                Text("Instruments and stress rigs for whoever works on Nuke. Caches are turned off where they would hide the work, and the screens report numbers rather than explain them – the catalog does that.")
            }
        }
        .navigationTitle("Lab")
    }
}

#Preview {
    NavigationStack {
        LabMenu()
            .demoDestinations()
    }
}
