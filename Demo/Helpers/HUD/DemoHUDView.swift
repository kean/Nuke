// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

extension View {
    /// Lays the pipeline HUD over this view while ``DemoHUD/isVisible``: a card
    /// in a corner, folded down to a pill, which opens into every figure and
    /// the buttons that open the pipeline's details.
    ///
    /// It floats over the screen rather than standing on it: it takes none of
    /// the safe area, and it is dragged from one corner to whichever one it is
    /// let go nearest.
    ///
    /// Applied once, around the navigation stack, so that it stays put as
    /// screens come and go.
    func demoPipelineHUD() -> some View {
        overlay {
            DemoHUDContainer(hud: .shared)
        }
    }
}

extension View {
    /// Marks this view as the one a sheet is opened from, so the sheet grows
    /// out of it rather than sliding up from the bottom edge. The demo runs on
    /// iOS 17, which slides as every sheet used to.
    @ViewBuilder
    fileprivate func demoZoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// The other half of ``demoZoomSource(id:in:)``, on the sheet's own root.
    @ViewBuilder
    fileprivate func demoZoomDestination(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

/// Places the HUD in the corner it stands in, above a console sheet, moves it
/// to the corner a drag leaves it nearest, keeps it sampled while the app is
/// active, and presents the **Pipeline Details** sheet its info button opens.
struct DemoHUDContainer: View {
    let hud: DemoHUD

    /// The container in the window: where a console sheet reports its top, and
    /// the halves that say which corner a dragged card belongs in.
    @State private var frame: CGRect = .zero
    /// How far the card has been dragged out of its corner; back to zero once
    /// it has settled into the one it was let go nearest.
    @State private var dragOffset: CGSize = .zero
    @Environment(\.scenePhase) private var scenePhase
    /// Ties the details sheet to the card it is opened from, so it zooms out
    /// of the HUD rather than sliding up from the bottom edge.
    @Namespace private var namespace

    /// The room the pill needs, which is the room the HUD starts out taking:
    /// the card's one row, the padding inside the card, and the padding
    /// around it. Measured after that – see `hud.height`.
    static let pillRoom: CGFloat = 22 + 12 + 12
    /// The room an inline navigation bar takes. The HUD is laid over the
    /// navigation stack rather than inside it, so the bar isn't in the safe
    /// area it is given: in a top corner it stands clear of the bar itself,
    /// rather than over the back button.
    private static let barRoom: CGFloat = 44

    var body: some View {
        if hud.isVisible {
            let lift = lift
            DemoHUDCard(hud: hud)
                // On the card itself, so that the rest of the overlay – the
                // room the card is free to be dragged through – stays out of
                // the way of the screen underneath.
                .gesture(drag)
                // The source is the card itself, not the width it is given to
                // grow into, so the sheet zooms out of what is on screen.
                .demoZoomSource(id: Self.cardTransitionID, in: namespace)
                // About the width of a phone: wider lines are hard to read
                // across. Folded away the card hugs its one row, so the frame
                // keeps it against the edge it stands on rather than centring
                // it.
                .frame(maxWidth: 420, alignment: hud.corner.isLeading ? .leading : .trailing)
                .padding(padding)
                // What a bottom corner needs to clear a console sheet. The card
                // grows and shrinks in one piece, so this follows it the whole
                // way rather than jumping when it settles.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { hud.height = $0 }
                .offset(dragOffset)
                .padding(.bottom, lift)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: hud.corner.alignment)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
                .animation(.snappy, value: lift)
                .task(id: scenePhase == .active) {
                    guard scenePhase == .active else { return }
                    await hud.sampleUntilCancelled()
                }
                .task {
                    guard DemoLaunchOptions.claimDetails() else { return }
                    // Long enough for a screen opened with `-demoScreen` to
                    // have arrived, and for a console of its own to be up,
                    // which the details step around.
                    try? await Task.sleep(for: .milliseconds(900))
                    hud.openDetails()
                }
                .sheet(isPresented: isShowingDetails) {
                    PipelineDetailsSheet()
                        .demoZoomDestination(id: Self.cardTransitionID, in: namespace)
                }
        }
    }

    private static let cardTransitionID = "hud-card"

    /// The room around the card: the two edges it stands on, and a little on
    /// the others, which is where it grows from. A top corner leaves the
    /// navigation bar its own room as well.
    private var padding: EdgeInsets {
        let isTop = hud.corner.isTop
        return EdgeInsets(top: isTop ? 8 + Self.barRoom : 4, leading: 8, bottom: isTop ? 4 : 8, trailing: 8)
    }

    /// Carries the card with the finger, and hands it to the corner of the
    /// half it is let go in – where a flick is going, rather than where it
    /// left off.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                let end = value.predictedEndLocation
                withAnimation(.snappy) {
                    hud.corner = DemoHUD.Corner(isTop: end.y < frame.midY, isLeading: end.x < frame.midX)
                    // Settles in one move with the corner it is going to,
                    // rather than snapping back and then sliding there.
                    dragOffset = .zero
                }
            }
    }

    /// The HUD owns whether the details are up – a console sheet has to step
    /// aside first – so the sheet reads the switch rather than holding one.
    private var isShowingDetails: Binding<Bool> {
        Binding { hud.isShowingDetails } set: { hud.isShowingDetails = $0 }
    }

    /// How far the HUD rises to stay above a console sheet. A sheet pulled up
    /// past the room the HUD needs covers it, as it covers the screen. A top
    /// corner is above every sheet already.
    private var lift: CGFloat {
        guard !hud.corner.isTop, let sheetMinY = hud.consoleSheetMinY else { return 0 }
        let covered = frame.maxY - sheetMinY
        let needed = hud.isExpanded ? hud.height : Self.pillRoom
        return covered > 0 && frame.height - covered >= needed ? covered : 0
    }
}

/// The HUD itself: one card, which is a row of figures folded away and every
/// figure the HUD has when it is open.
///
/// It is one view in both states rather than a pill swapped for a panel, so
/// opening it is the card growing – the icon stays where it is, the chevron
/// turns over, and the rows are revealed as there becomes room for them –
/// rather than one view fading into another.
private struct DemoHUDCard: View {
    let hud: DemoHUD

    /// Whether the options popover is up, which the ellipsis opens.
    @State private var isShowingOptions = false

    private var isExpanded: Bool { hud.isExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if isExpanded {
                figures
                    .transition(Self.unfold)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, isExpanded ? 12 : 6)
        // The shape the card is cut to as well as drawn in: a row that is
        // there before there is room for it is clipped away rather than
        // hanging over the edge while the card catches up. Folded, the radius
        // is half the row's height – a capsule, as the system's own glass
        // controls are at that size.
        .demoHUDBackground(in: RoundedRectangle(cornerRadius: isExpanded ? 18 : 17, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isExpanded else { return }
            hud.isExpanded = true
        }
        .animation(.snappy, value: isExpanded)
        .accessibilityElement(children: .contain)
        // On the whole card rather than on the button that opens it, so that
        // the popover is laid beside the card instead of over it: a popover
        // falls under the card's glass, which is drawn above every
        // presentation but a sheet's.
        .demoOptionsPopover(isPresented: $isShowingOptions) {
            DemoOptionRow(title: "Reset Figures", systemImage: "arrow.counterclockwise") {
                choose { hud.reset() }
            }
            if hud.pinnedID != nil {
                DemoOptionRow(title: "Follow Active Pipeline", systemImage: "pin.slash") {
                    choose { hud.pinnedID = nil }
                }
            }
            DemoOptionRow(title: "Hide HUD", systemImage: "eye.slash") {
                choose { hud.isVisible = false }
            }
            Divider()
            ForEach(DemoHUD.Corner.allCases) { corner in
                DemoOptionRow(title: corner.title, systemImage: corner.systemImage, isChosen: corner == hud.corner) {
                    choose { withAnimation(.snappy) { hud.corner = corner } }
                }
            }
        }
    }

    /// Closes the popover and then does what the row said, as a menu does.
    private func choose(_ action: () -> Void) {
        isShowingOptions = false
        action()
    }

    /// Rows fade in as the card makes room for them, and go at once when it
    /// takes the room back: a view being removed holds its place in the layout
    /// until its transition ends, so a fade out would keep the card open until
    /// it finished and then let it snap shut.
    private static let unfold: AnyTransition = .asymmetric(insertion: .opacity, removal: .identity)

    /// The one row the card always has: what the HUD is following, the figures
    /// worth a glance while it is folded away, and the controls.
    private var header: some View {
        HStack(spacing: 8) {
            // The pin says the HUD is held to this pipeline rather than
            // following whichever one is busy – see `DemoHUD/pinnedID`.
            Image(systemName: hud.pinnedID == nil ? "gauge.with.needle" : "pin.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            if isExpanded {
                Text(hud.followed?.figures.label ?? "No pipeline")
                    .lineLimit(1)
                    .transition(Self.unfold)
                Spacer(minLength: 8)
                optionsButton
                    .transition(Self.unfold)
            } else {
                glance
                    .transition(Self.unfold)
            }
            // Folded or open, the details are one tap away rather than a tap
            // into the options: they are what the HUD is usually opened for.
            button("Pipeline Details", "info.circle") {
                hud.openDetails()
            }
            button(isExpanded ? "Collapse" : "Expand", "chevron.down") {
                hud.isExpanded.toggle()
            }
            .rotationEffect(.degrees(isExpanded ? 0 : 180))
        }
        .font(.system(size: 12, weight: .semibold))
        .frame(height: 22)
    }

    /// The three figures the folded card shows, in the monospaced style the
    /// open one sets them in.
    private var glance: some View {
        let stats = Array(hud.panelStats.prefix(3))
        return HStack(spacing: 9) {
            ForEach(stats) { stat in
                Text(stat.value).foregroundStyle(stat.tint ?? Color.primary)
                    + Text(verbatim: " \(stat.caption)").foregroundStyle(Color.secondary)
            }
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pipeline HUD")
        .accessibilityValue(stats.map { "\($0.value) \($0.caption)" }.joined(separator: ", "))
    }

    /// Every figure of the pipeline the HUD follows and of the app: the four
    /// that matter most, the task queues, and the rest in two columns that
    /// line up under them.
    private var figures: some View {
        let followed = hud.followed
        let figures = followed?.figures ?? DemoPipelineDiagnostics()
        return VStack(alignment: .leading, spacing: 0) {
            DemoHUDStats(stats: hud.panelStats)
            rule
            DemoHUDQueues(queues: DemoHUD.queues(figures))
            rule
            DemoFieldGrid(groups: hud.cardFields(figures, caches: followed.flatMap { hud.caches[$0.id] }))
        }
    }

    /// What separates one group of figures from the next: a hairline rather
    /// than a gap, as the groups are a few lines each and space alone doesn't
    /// hold them apart at this size.
    private var rule: some View {
        Divider().padding(.vertical, 9)
    }

    /// Everything else the HUD can do, which the catalog leaves to it: where
    /// it stands, for whoever would rather not drag it, and the switches.
    private var optionsButton: some View {
        button("HUD Options", "ellipsis") {
            isShowingOptions = true
        }
    }

    private func button(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

extension View {
    /// A popover that stands in for a menu, holding rows of ``DemoOptionRow``.
    ///
    /// A popover rather than a menu in both places the HUD's instruments have
    /// one, for two different reasons. Over the card, a menu is drawn *under*
    /// the card's Liquid Glass, which swallows every row that falls behind it;
    /// inside a sheet held dark, a menu is presented by UIKit and follows the
    /// window, so it comes up light whatever the sheet is set to. The popover
    /// is laid out against the bounds of whatever it is attached to, so the
    /// card attaches it to itself and is stepped around rather than covered.
    func demoOptionsPopover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        popover(isPresented: isPresented, attachmentAnchor: .rect(.bounds)) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.vertical, 6)
            .frame(width: 230)
            .presentationCompactAdaptation(.popover)
            // The scheme sets the rows, and the background the chrome around
            // them: a popover's own is glass over the screen, which comes out
            // as pale as the HUD's card did before it was tinted.
            .preferredColorScheme(.dark)
            .presentationBackground(Color(white: 0.13))
        }
    }
}

/// A row of an options popover, which reads as a menu's does: a title, the
/// symbol it goes by, and a check against the one in force.
struct DemoOptionRow: View {
    let title: String
    let systemImage: String
    var isChosen = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isChosen ? "checkmark" : systemImage)
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The figures the HUD leads with, in a row of columns of equal width: the
/// card and the **Pipeline Details** sheet set the same row at two sizes.
struct DemoHUDStats: View {
    let stats: [DemoHUD.Stat]
    /// The size the values are set at. The unit after a value follows it; the
    /// caption under it doesn't, as it is already as small as it reads at.
    var size: CGFloat = 21

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 1) {
                    value(stat)
                        .foregroundStyle(stat.tint ?? Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(stat.caption.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func value(_ stat: DemoHUD.Stat) -> Text {
        let value = Text(stat.value)
            .font(.system(size: size, weight: .medium, design: .monospaced))
        guard let unit = stat.unit else { return value }
        return value + Text(verbatim: " \(unit)")
            .font(.system(size: size * 0.62, weight: .medium, design: .monospaced))
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
        // A column apiece, of the width the figures above them take, so that
        // the queues read as one more row of the card rather than a line of
        // text that happens to have blocks in it.
        HStack(spacing: 8) {
            ForEach(queues) { queue in
                row(queue)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 11, design: .monospaced))
    }

    private func row(_ queue: DemoHUD.Queue) -> some View {
        HStack(spacing: 5) {
            Text(queue.name)
                .foregroundStyle(.secondary)
            if (1...Self.maxSlots).contains(queue.limit) {
                DemoQueueSlots(running: queue.running ?? 0, limit: queue.limit, isSuspended: queue.isSuspended, size: CGSize(width: 5, height: 12))
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

/// A slot per unit of a queue's limit, filled while work runs in it and orange
/// while the queue is suspended. The HUD and the details sheet draw the same
/// row at different sizes.
struct DemoQueueSlots: View {
    let running: Int
    let limit: Int
    var isSuspended = false
    var size = CGSize(width: 6, height: 11)
    /// The color of a slot with work in it, or `nil` for the green the HUD
    /// uses over its dark card.
    var tint: Color?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(0, limit), id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < running ? (isSuspended ? Color.orange : (tint ?? .green)) : Color.primary.opacity(0.18))
                    .frame(width: size.width, height: size.height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Figures in two columns of equal width, each a label at the left of its
/// column and the figure at the right.
///
/// The columns are read down, not across: each is a group of its own, and the
/// rows only pair them up. Every figure ends at the same edge, so a count that
/// grows from 9 to 10 moves nothing around it – which is what the lines this
/// replaced padded their values out to manage.
struct DemoFieldGrid: View {
    let groups: [DemoHUD.FieldGroup]
    var size: CGFloat = 11
    /// The room between one group and the next, where the caller sets the
    /// groups apart itself rather than leaving them a rule.
    var spacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Divider().padding(.vertical, spacing)
                }
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 3) {
                    ForEach(0..<group.rowCount, id: \.self) { row in
                        GridRow {
                            cell(group.leading, row)
                            cell(group.trailing, row)
                        }
                    }
                }
            }
        }
        .font(.system(size: size, design: .monospaced))
    }

    /// One field of a column, or the room it would have taken where the
    /// column is shorter than the one beside it.
    @ViewBuilder
    private func cell(_ fields: [DemoHUD.Field], _ row: Int) -> some View {
        if row < fields.count {
            let field = fields[row]
            HStack(spacing: 6) {
                Text(field.label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(field.value)
                    .foregroundStyle(field.tint ?? Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
        }
    }
}

/// What the HUD's glass is tinted with, and what the blur behind it was before
/// there was glass: enough black to read light figures over a white screen.
private let demoHUDTint = Color.black.opacity(0.7)

extension View {
    /// The card's background: Liquid Glass, which takes the screen's own light
    /// and lifts the card off it, where the system has it. The content is cut
    /// to the same shape, so a card that is still growing shows only as much
    /// of a row as it has room for.
    ///
    /// Dark whatever the app is set in, as the **Pipeline Details** sheet is:
    /// the HUD is an instrument laid over the screen rather than part of it,
    /// and a dark card reads as one over a light screen as well as a dark one.
    fileprivate func demoHUDBackground(in shape: some Shape) -> some View {
        Group {
            if #available(iOS 26, *) {
                // Tinted rather than left to the screen. Glass takes its colour
                // from what is behind it, and the colour scheme doesn't enter
                // into it: over a light screen an untinted card comes out a pale
                // grey that the figures are lost in, and the folded pill, which
                // is thinner, paler still. A dark tint holds the card dark over
                // anything while the glass keeps its edge and its refraction.
                //
                // Interactive, so the glass answers the tap that opens the card
                // and the drag that carries it to another corner.
                clipShape(shape)
                    .glassEffect(.regular.tint(demoHUDTint).interactive(), in: shape)
            } else {
                demoHUDBlurBackground(in: shape)
            }
        }
        // The figures are set for a dark card whichever background drew it.
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.primary)
    }

    /// What the card stood in before Liquid Glass: light figures on a dark
    /// blur, which read over photos and text alike, lifted off the screen by a
    /// shadow.
    fileprivate func demoHUDBlurBackground(in shape: some Shape) -> some View {
        self
            .clipShape(shape)
            .background {
                shape
                    .fill(demoHUDTint)
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
    }
}

/// Suspends until the task it runs in is cancelled: the body of a `task` that
/// holds something open for as long as its view is on screen.
func demoWaitUntilCancelled() async {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3600))
    }
}
