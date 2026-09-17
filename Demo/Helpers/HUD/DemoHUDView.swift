// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

extension View {
    /// Lays the pipeline HUD over this view while ``DemoHUD/isVisible``: a pill
    /// at the bottom with the headline figures, which opens into a panel with
    /// all of them.
    ///
    /// Applied once, around the navigation stack, so that every screen has it
    /// and it stays put as screens come and go. It presents nothing – no
    /// sheet, no inspector – so it can't get in the way of a screen's own
    /// console or explanation, and it takes touches only where it is drawn.
    ///
    /// Every screen on the stack makes room for the pill with
    /// ``demoHUDRoom()``. A console sheet covers that room, so the HUD rises
    /// above the sheet instead (``DemoHUD/consoleSheetMinY``).
    func demoPipelineHUD() -> some View {
        overlay {
            DemoHUDOverlay()
        }
    }

    /// Takes a strip off the bottom of the safe area while the HUD is on, where
    /// its pill sits: a list scrolls its last row above the pill, and a stage
    /// ends before it.
    ///
    /// Applied to every screen rather than once around the navigation stack,
    /// whose screens don't inherit a safe area set outside it.
    func demoHUDRoom() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            DemoHUDRoom()
        }
    }
}

private struct DemoHUDOverlay: View {
    var body: some View {
        if DemoHUD.shared.isVisible {
            DemoHUDContainer(hud: .shared)
        }
    }
}

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
        // A button rather than a toggle: a toggle styled as a button fills
        // its whole background when on, which is too loud for a bar button.
        Button {
            hud.isVisible.toggle()
        } label: {
            Label("Pipeline HUD", systemImage: "gauge.with.needle")
                .symbolVariant(hud.isVisible ? .fill : .none)
        }
        .accessibilityAddTraits(hud.isVisible ? .isSelected : [])
    }
}

/// Places the HUD at the bottom, moves it to the other end when it is
/// dragged, keeps it above a console sheet, and keeps the figures sampled
/// while it is on screen and the app is active.
private struct DemoHUDContainer: View {
    let hud: DemoHUD

    @State private var dragOffset: CGFloat = 0
    /// The container in the window, which is where a console sheet reports its
    /// top.
    @State private var frame: CGRect = .zero
    @Environment(\.scenePhase) private var scenePhase

    static let pillHeight: CGFloat = 28
    private static let margin: CGFloat = 8
    private static let bottomMargin: CGFloat = 4
    /// The strip the HUD takes off the bottom of every screen.
    static let reservedHeight = pillHeight + margin + bottomMargin
    private static let space = "DemoHUD"

    var body: some View {
        let lift = lift
        content
            .padding(.horizontal, Self.margin)
            .padding(.top, Self.margin)
            .padding(.bottom, Self.bottomMargin + lift)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: hud.edge == .leading ? .bottomLeading : .bottomTrailing)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .coordinateSpace(.named(Self.space))
            .animation(.snappy, value: hud.edge)
            .animation(.snappy, value: hud.isExpanded)
            .animation(.snappy, value: lift)
            .task(id: scenePhase == .active) {
                guard scenePhase == .active else { return }
                hud.startSampling()
                defer { hud.stopSampling() }
                await demoWaitUntilCancelled()
            }
    }

    @ViewBuilder
    private var content: some View {
        if hud.isExpanded {
            DemoHUDPanel(hud: hud, drag: drag)
                // About the width of a phone in portrait: as wide as the lines
                // get before they are hard to read across.
                .frame(maxWidth: 420)
                .offset(x: dragOffset)
        } else {
            DemoHUDPill(hud: hud)
                .frame(height: Self.pillHeight)
                .offset(x: dragOffset)
                .gesture(drag)
        }
    }

    /// Follows the finger, then settles at the end of the bottom edge the HUD
    /// was thrown toward.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.space))
            .onChanged { dragOffset = $0.translation.width }
            .onEnded { value in
                withAnimation(.snappy) {
                    hud.edge = value.predictedEndLocation.x < frame.width / 2 ? .leading : .trailing
                    dragOffset = 0
                }
            }
    }

    /// How far the HUD rises to stay above a console sheet. A sheet pulled up
    /// past the room the HUD needs covers it, the way it covers the screen.
    private var lift: CGFloat {
        guard let sheetMinY = hud.consoleSheetMinY, frame.height > 0 else {
            return 0
        }
        let covered = frame.maxY - sheetMinY
        let needed = hud.isExpanded ? 160 : Self.reservedHeight
        guard covered > 0, frame.height - covered >= needed else {
            return 0
        }
        return covered
    }
}

/// The HUD folded away: three figures, and a tap opens the panel.
private struct DemoHUDPill: View {
    let hud: DemoHUD

    var body: some View {
        let headline = DemoHUDFigures.headline(hud.figures, display: hud.display)
        Button {
            hud.isExpanded = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.needle")
                Text(verbatim: headline)
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .demoHUDBackground(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pipeline HUD")
        .accessibilityValue(headline)
        .accessibilityHint("Shows every figure.")
    }
}

/// Every figure, under a bar with the pipeline they are for, the time since
/// they were reset, and the buttons.
private struct DemoHUDPanel<Drag: Gesture>: View {
    let hud: DemoHUD
    let drag: Drag

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            // Scrolls only where the screen is too short for it, such as a
            // phone on its side or above a console pulled up halfway.
            ViewThatFits(in: .vertical) {
                lines
                ScrollView { lines }
            }
        }
        .padding(10)
        .demoHUDBackground(in: RoundedRectangle(cornerRadius: 14))
    }

    private var lines: some View {
        DemoHUDLinesView(groups: DemoHUDFigures.groups(
            hud.figures,
            caches: hud.selectedCaches,
            display: hud.display,
            footprint: hud.footprint
        ))
    }

    private var header: some View {
        HStack(spacing: 10) {
            DemoHUDPipelineMenu(hud: hud, selection: hud.selection, choices: hud.choices, followed: hud.followed)
                .equatable()
            Text(hud.resetDate, style: .timer)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel("Since the reset")
            Spacer(minLength: 8)
            Button {
                hud.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 28, height: 24)
            }
            .accessibilityLabel("Reset")
            Button {
                hud.isExpanded = false
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .frame(width: 28, height: 24)
            }
            .accessibilityLabel("Collapse")
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.plain)
        // The bar is the handle the panel is dragged by; the figures under it
        // scroll where they have to.
        .contentShape(Rectangle())
        .gesture(drag)
    }
}

/// The pipeline the figures are for, and the others to pick from.
///
/// Equatable, as the menus of the animation screens are: the panel redraws ten
/// times a second, and a menu rebuilt that often pulls its items out from
/// under the finger on its way to one.
private struct DemoHUDPipelineMenu: View, Equatable {
    let hud: DemoHUD
    let selection: DemoHUD.Selection
    let choices: [DemoHUD.Choice]
    let followed: DemoHUD.Choice?

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selection == rhs.selection && lhs.choices == rhs.choices && lhs.followed == rhs.followed
    }

    var body: some View {
        Menu {
            Picker("Pipeline", selection: Binding(get: { selection }, set: { hud.select($0) })) {
                VStack {
                    Text("Automatic")
                    Text(followed.map { "Following \($0.label)" } ?? "The pipeline that did something last")
                }
                .tag(DemoHUD.Selection.automatic)
                Text("All Pipelines").tag(DemoHUD.Selection.all)
                ForEach(choices) { choice in
                    Text(choice.label).tag(DemoHUD.Selection.pipeline(choice.id))
                }
            }
            Divider()
            Button("Hide HUD", systemImage: "eye.slash") {
                hud.isVisible = false
            }
        } label: {
            HStack(spacing: 4) {
                Text(hud.title)
                    .lineLimit(1)
                if selection == .automatic {
                    Text("auto")
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .foregroundStyle(.primary)
        }
        .accessibilityLabel("Pipeline")
        .accessibilityValue(hud.title)
    }
}

extension View {
    /// Light figures on a dark, blurred ground, which reads over photos and
    /// over the text of a list alike: a plain translucent fill lets the rows
    /// beneath show through the figures.
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
