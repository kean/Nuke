// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

extension View {
    /// Lays the pipeline HUD over this view while ``DemoHUD/isVisible``: a pill
    /// at the bottom, which opens into a panel with every figure.
    ///
    /// Applied once, around the navigation stack, so that it stays put as
    /// screens come and go. It presents nothing, so it can't get in the way of
    /// a screen's own sheets.
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

// Views of their own, so that a screen's body doesn't depend on the switch.
private struct DemoHUDRoom: View {
    var body: some View {
        if DemoHUD.shared.isVisible {
            Color.clear
                .frame(height: DemoHUDContainer.reservedHeight)
                .allowsHitTesting(false)
        }
    }
}

/// The button in the navigation bar of every screen that shows and hides the
/// HUD. ``View/demoInfoButton(isPresented:)`` puts it beside the question mark.
struct DemoHUDToggle: View {
    var body: some View {
        let hud = DemoHUD.shared
        // A toggle styled as a button fills its background when on, which is
        // too loud for a bar button.
        Button {
            hud.isVisible.toggle()
        } label: {
            Label("Pipeline HUD", systemImage: "gauge.with.needle")
                .symbolVariant(hud.isVisible ? .fill : .none)
        }
        .accessibilityAddTraits(hud.isVisible ? .isSelected : [])
    }
}

/// Places the HUD at the bottom, above a console sheet, and keeps it sampled
/// while the app is active.
private struct DemoHUDContainer: View {
    let hud: DemoHUD

    /// The container in the window, where a console sheet reports its top.
    @State private var frame: CGRect = .zero
    @Environment(\.scenePhase) private var scenePhase

    private static let pillHeight: CGFloat = 28
    static let reservedHeight = pillHeight + 12

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
            .padding(.bottom, 4 + lift)
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
        let needed = hud.isExpanded ? 200 : Self.reservedHeight
        return covered > 0 && frame.height - covered >= needed ? covered : 0
    }
}

/// The HUD folded away: a tap opens the panel.
private struct DemoHUDPill: View {
    let hud: DemoHUD

    var body: some View {
        let headline = hud.headline
        Button {
            hud.isExpanded = true
        } label: {
            Label(headline, systemImage: "gauge.with.needle")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)
                .demoHUDBackground(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pipeline HUD")
        .accessibilityValue(headline)
    }
}

/// The figures of the pipeline the HUD follows, and of the app.
private struct DemoHUDPanel: View {
    let hud: DemoHUD

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(hud.followed?.figures.label ?? "No pipeline")
                    .lineLimit(1)
                Spacer(minLength: 8)
                button("Reset", "arrow.counterclockwise") { hud.reset() }
                button("Collapse", "arrow.down.right.and.arrow.up.left") { hud.isExpanded = false }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
            DemoHUDLines(groups: [
                DemoHUD.lines(hud.followed?.figures ?? DemoPipelineDiagnostics(), caches: hud.followed.flatMap { hud.caches[$0.id] }),
                hud.appLines
            ])
        }
        .padding(10)
        .demoHUDBackground(in: RoundedRectangle(cornerRadius: 14))
    }

    private func button(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
    }
}

/// Lines of figures in a monospaced block, the labels in a column.
struct DemoHUDLines: View {
    let groups: [[(String, String)]]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
            ForEach(groups.indices, id: \.self) { index in
                if index > 0 {
                    Divider().padding(.vertical, 3)
                }
                ForEach(groups[index], id: \.0) { line in
                    GridRow {
                        Text(line.0).foregroundStyle(.secondary)
                        Text(line.1).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .font(.system(size: 10, design: .monospaced))
    }
}

extension View {
    /// Light figures on a dark blur, which read over photos and text alike.
    fileprivate func demoHUDBackground(in shape: some Shape) -> some View {
        self
            .background {
                shape
                    .fill(Color.black.opacity(0.6))
                    .background(.regularMaterial, in: shape)
            }
            .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 0.5))
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
