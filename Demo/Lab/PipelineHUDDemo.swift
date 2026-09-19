// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// The switch of the pipeline HUD, and its lines for every pipeline alive at
/// once, where the HUD shows one.
struct PipelineHUDDemo: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var hud = DemoHUD.shared
        List {
            Section {
                Toggle("Show HUD", isOn: $hud.isVisible)
                Toggle("Expanded", isOn: $hud.isExpanded)
                    .disabled(!hud.isVisible)
                Button("Reset") {
                    hud.reset()
                }
            }
            Section("App") {
                lines(hud.appLines)
            }
            Section("All Pipelines") {
                lines(DemoHUD.lines(hud.total, caches: hud.totalCaches))
            }
            ForEach(hud.pipelines) { pipeline in
                Section(pipeline.figures.label) {
                    lines(DemoHUD.lines(pipeline.figures, caches: hud.caches[pipeline.id]))
                }
            }
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await hud.sampleUntilCancelled()
        }
        .demoInfo(Self.info)
    }

    /// With narrow insets, as the lines are set for the width of the HUD.
    private func lines(_ lines: [(String, String)]) -> some View {
        DemoHUDLines(groups: [lines])
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
    }

    private static let info = DemoInfo(
        "Pipeline HUD",
        "What each pipeline in the demo has done since the last reset, as the probe it is built with counts it, and what the app's memory and the display are doing.",
        points: [
            .init("Switching it on", "The gauge in the navigation bar of every screen, or `-demoHUD 1` at launch; `-demoHUD expanded` opens the panel."),
            .init("Which pipeline", "The HUD follows the pipeline that did something last, and holds on to it while it keeps busy."),
            .init("Source", "Where the images came from: a download, `URLCache` and fixtures included; `DataCache`; or the memory cache, with or without a task. Hit is the share that didn't download."),
            .init("Blind spots", "Work waiting in a queue, processing, and frames the render server drops. The caches are read every 3 seconds.")
        ]
    )
}
