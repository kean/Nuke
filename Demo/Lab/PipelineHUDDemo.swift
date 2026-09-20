// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// The switches of the pipeline HUD, and its figures for every pipeline alive
/// at once, where the HUD itself shows the one it follows.
///
/// Opened from the HUD's menu: the catalog has no row for it.
struct PipelineHUDDemo: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var hud = DemoHUD.shared
        List {
            Section {
                Toggle("Show HUD", isOn: $hud.isVisible)
                Toggle("Expanded", isOn: $hud.isExpanded)
                    .disabled(!hud.isVisible)
                Button("Reset Figures") {
                    hud.reset()
                }
            } footer: {
                Text("The HUD stands over every screen and shows the pipeline that did something last. The Lab section of the catalog has the same switch.")
            }
            Section("App") {
                stats(hud.appStats)
                lines(hud.appLines)
            }
            Section("All Pipelines") {
                figures(hud.total, caches: hud.totalCaches)
            }
            ForEach(hud.pipelines) { pipeline in
                Section(pipeline.figures.label) {
                    figures(pipeline.figures, caches: hud.caches[pipeline.id])
                }
            }
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await hud.sampleUntilCancelled()
        }
        .demoInfo(Self.info)
    }

    /// One pipeline, laid out the way the HUD's panel lays it out.
    @ViewBuilder
    private func figures(_ figures: DemoPipelineDiagnostics, caches: DemoPipelineDiagnostics.Caches?) -> some View {
        stats(DemoHUD.stats(figures))
        row {
            DemoHUDQueues(queues: DemoHUD.queues(figures))
        }
        lines(DemoHUD.lines(figures, caches: caches))
    }

    private func stats(_ stats: [DemoHUD.Stat]) -> some View {
        row {
            DemoHUDStats(stats: stats)
                .frame(maxWidth: 280, alignment: .leading)
        }
    }

    private func lines(_ lines: [DemoHUD.Line]) -> some View {
        row {
            DemoHUDLines(groups: [lines])
        }
    }

    /// With narrow insets, as the figures are set for the width of the HUD.
    private func row(@ViewBuilder content: () -> some View) -> some View {
        content()
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
    }

    private static let info = DemoInfo(
        "Pipeline HUD",
        "What each pipeline in the demo has done since the last reset, as the probe it is built with counts it, and what the app's memory and the display are doing. The HUD over every screen shows the same figures for one pipeline at a time.",
        points: [
            .init("Switching it on", "It is on from launch. The Lab section of the catalog has the switch, the HUD's own menu hides it, and `-demoHUD 0` leaves it off; `-demoHUD expanded` opens the panel."),
            .init("Which pipeline", "The HUD follows the pipeline that did something last, and holds on to it while it keeps busy. This screen shows them all."),
            .init("Source", "Where the images came from: a download, `URLCache` and fixtures included; `DataCache`; or the memory cache, with or without a task. Hit is the share that didn't download."),
            .init("Queues", "The work running on each queue against its limit, a slot apiece. A total adds up the limits of every pipeline alive, so it is written as a count."),
            .init("Blind spots", "Work waiting in a queue, processing, and frames the render server drops. The caches are read every 3 seconds.")
        ]
    )
}
