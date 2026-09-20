// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

extension View {
    /// Lays the pipeline HUD over this view while ``DemoHUD/isVisible``: a pill
    /// at the bottom, which opens into a panel with every figure and the menu
    /// that opens the pipeline's details.
    ///
    /// Applied once, around the navigation stack, so that it stays put as
    /// screens come and go. It presents nothing but its menu, so it can't get
    /// in the way of a screen's own sheets.
    func demoPipelineHUD() -> some View {
        overlay {
            DemoHUDContainer(hud: .shared)
        }
    }

    /// Takes a strip off the bottom of the safe area for the pill while the
    /// HUD is on. Applied to every screen: a screen in a navigation stack
    /// doesn't inherit a safe area set outside it.
    func demoHUDRoom() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            DemoHUDRoom()
        }
    }
}

// A view of its own, so that a screen's body doesn't depend on the switch.
private struct DemoHUDRoom: View {
    var body: some View {
        let hud = DemoHUD.shared
        if hud.isVisible {
            Color.clear
                .frame(height: hud.height)
                .allowsHitTesting(false)
                .animation(.snappy, value: hud.height)
        }
    }
}

/// Places the HUD at the bottom, above a console sheet, and keeps it sampled
/// while the app is active.
struct DemoHUDContainer: View {
    let hud: DemoHUD

    /// The container in the window, where a console sheet reports its top.
    @State private var frame: CGRect = .zero
    @Environment(\.scenePhase) private var scenePhase

    private static let pillHeight: CGFloat = 30
    /// The room the pill needs, which is the room the HUD starts out taking.
    static let pillRoom = pillHeight + 12

    var body: some View {
        if hud.isVisible {
            let lift = lift
            Group {
                if hud.isExpanded {
                    // About the width of a phone: wider lines are hard to read across.
                    DemoHUDPanel(hud: hud).frame(maxWidth: 420)
                } else {
                    DemoHUDPill(hud: hud).frame(height: Self.pillHeight)
                }
            }
            .padding([.horizontal, .top], 8)
            .padding(.bottom, 4)
            // The room every screen leaves at the bottom: the panel is as tall
            // as its figures, and a screen scrolled to the end clears it.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { hud.height = $0 }
            .padding(.bottom, lift)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .animation(.snappy, value: hud.isExpanded)
            .animation(.snappy, value: lift)
            .task(id: scenePhase == .active) {
                guard scenePhase == .active else { return }
                await hud.sampleUntilCancelled()
            }
        }
    }

    /// How far the HUD rises to stay above a console sheet. A sheet pulled up
    /// past the room the HUD needs covers it, as it covers the screen.
    private var lift: CGFloat {
        guard let sheetMinY = hud.consoleSheetMinY else { return 0 }
        let covered = frame.maxY - sheetMinY
        let needed = hud.isExpanded ? hud.height : Self.pillRoom
        return covered > 0 && frame.height - covered >= needed ? covered : 0
    }
}

/// The HUD folded away: the three figures worth a glance, and a tap to open
/// the panel.
private struct DemoHUDPill: View {
    let hud: DemoHUD

    var body: some View {
        let stats = Array(hud.panelStats.prefix(3))
        Button {
            hud.isExpanded = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(stats) { stat in
                    Text(stat.value).foregroundStyle(stat.tint ?? Color.primary)
                        + Text(verbatim: " \(stat.caption)").foregroundStyle(Color.secondary)
                }
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 11)
            .frame(maxHeight: .infinity)
            .demoHUDBackground(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pipeline HUD")
        .accessibilityValue(stats.map { "\($0.value) \($0.caption)" }.joined(separator: ", "))
        .accessibilityHint("Opens the panel")
    }
}

/// The figures of the pipeline the HUD follows and of the app: the four that
/// matter most, the task queues, and a line each for the rest.
private struct DemoHUDPanel: View {
    let hud: DemoHUD

    @Environment(\.demoOpen) private var open

    var body: some View {
        let followed = hud.followed
        let figures = followed?.figures ?? DemoPipelineDiagnostics()
        VStack(alignment: .leading, spacing: 10) {
            header(label: followed?.figures.label ?? "No pipeline")
            DemoHUDStats(stats: hud.panelStats)
            DemoHUDQueues(queues: DemoHUD.queues(figures))
            DemoHUDLines(groups: [
                DemoHUD.lines(figures, caches: followed.flatMap { hud.caches[$0.id] }),
                hud.appLines
            ])
        }
        .padding(12)
        .demoHUDBackground(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func header(label: String) -> some View {
        HStack(spacing: 6) {
            // The pin says the HUD is held to this pipeline rather than
            // following whichever one is busy – see `DemoHUD/pinnedID`.
            Image(systemName: hud.pinnedID == nil ? "gauge.with.needle" : "pin.fill")
                .foregroundStyle(.secondary)
            Text(label)
                .lineLimit(1)
            Spacer(minLength: 8)
            menu
            button("Collapse", "chevron.down") { hud.isExpanded = false }
        }
        .font(.system(size: 11, weight: .semibold))
    }

    /// Everything the HUD can do, and the details of the pipeline it shows,
    /// which the catalog leaves to it.
    private var menu: some View {
        Menu {
            Button("Pipeline Details", systemImage: "list.bullet.rectangle") {
                // Folds the panel away on the way out: the screen it pushes
                // has the same figures, and room for them.
                hud.isExpanded = false
                open?(.pipelineDetails)
            }
            Button("Reset Figures", systemImage: "arrow.counterclockwise") {
                hud.reset()
            }
            if hud.pinnedID != nil {
                Button("Follow Active Pipeline", systemImage: "pin.slash") {
                    hud.pinnedID = nil
                }
            }
            Button("Hide HUD", systemImage: "eye.slash") {
                hud.isVisible = false
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("HUD Options")
    }

    private func button(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// The figures the HUD leads with, in a row of columns.
struct DemoHUDStats: View {
    let stats: [DemoHUD.Stat]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 1) {
                    Text(stat.value)
                        .font(.system(size: 19, weight: .medium, design: .monospaced))
                        .foregroundStyle(stat.tint ?? Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(stat.caption.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The task queues, a slot each: filled while work runs in it, and orange
/// while the queue is suspended.
struct DemoHUDQueues: View {
    let queues: [DemoHUD.Queue]

    /// Past this, the slots are a count instead: a total adds up the limits of
    /// every pipeline alive, and a row of 30 slots says nothing.
    private static let maxSlots = 8

    var body: some View {
        HStack(spacing: 14) {
            ForEach(queues) { queue in
                row(queue)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 10, design: .monospaced))
    }

    private func row(_ queue: DemoHUD.Queue) -> some View {
        HStack(spacing: 5) {
            Text(queue.name)
                .foregroundStyle(.secondary)
            if let running = queue.running, (1...Self.maxSlots).contains(queue.limit) {
                HStack(spacing: 2) {
                    ForEach(0..<queue.limit, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(index < running ? (queue.isSuspended ? Color.orange : .green) : Color.primary.opacity(0.18))
                            .frame(width: 5, height: 11)
                    }
                }
            } else {
                Text(verbatim: "\(queue.running.map { "\($0)" } ?? "–")/\(queue.limit)")
            }
            if queue.isSuspended {
                Text("paused")
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(queue.name) queue")
        .accessibilityValue("\(queue.running.map { "\($0)" } ?? "unknown") of \(queue.limit) running" + (queue.isSuspended ? ", paused" : ""))
    }
}

/// Lines of figures in a monospaced block, the labels in a column.
struct DemoHUDLines: View {
    let groups: [[DemoHUD.Line]]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
            ForEach(groups.indices, id: \.self) { index in
                if index > 0 {
                    Divider().padding(.vertical, 3)
                }
                ForEach(groups[index]) { line in
                    GridRow {
                        Text(line.label)
                            .foregroundStyle(.secondary)
                        Text(line.value)
                            .foregroundStyle(line.tint ?? Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .font(.system(size: 10, design: .monospaced))
    }
}

extension View {
    /// Light figures on a dark blur, which read over photos and text alike,
    /// lifted off the screen by a shadow.
    fileprivate func demoHUDBackground(in shape: some Shape) -> some View {
        self
            .background {
                shape
                    .fill(Color.black.opacity(0.55))
                    .background(.regularMaterial, in: shape)
            }
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.3), Color.white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.primary)
    }
}

/// Suspends until the task it runs in is cancelled: the body of a `task` that
/// holds something open for as long as its view is on screen.
func demoWaitUntilCancelled() async {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3600))
    }
}
