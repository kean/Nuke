// Temporary: tells apart "no frames on the runner" from a LazyImage bug, and
// tries the signals that don't need frames. Fails on purpose, so that CI keeps
// the xcresult with the numbers.

import Testing
import Foundation
import SwiftUI
@testable import Nuke
@testable import NukeUI

#if !os(watchOS)

#if os(macOS)
import AppKit
private final class Ticker: NSObject {
    var count = 0
    @objc func tick(_ link: CADisplayLink) { count += 1 }
}
#endif

@MainActor
private final class DiagLog {
    var activeBuilt = 0
    var inBetween = 0
    var identityBelowOne = 0
    var activeAnimated = 0
    var anyAnimated = 0
    var outerAnimated = 0
    var customAnimationCalls = 0

    var text: String {
        "activeBuilt=\(activeBuilt) inBetween=\(inBetween) identityBelowOne=\(identityBelowOne) activeAnimated=\(activeAnimated) anyAnimated=\(anyAnimated) outerAnimated=\(outerAnimated) customCalls=\(customAnimationCalls)"
    }

    /// An animation that reports being asked for a value, which is SwiftUI
    /// starting it, whether or not a frame follows.
    var animation: Animation {
        if #available(iOS 17, tvOS 17, macOS 14, visionOS 1, *) {
            Animation(Probe(log: self))
        } else {
            .linear(duration: 0.05)
        }
    }

    var transition: AnyTransition {
        .modifier(active: Recorder(log: self, isActive: true, progress: 0), identity: Recorder(log: self, isActive: false, progress: 1))
    }

    private struct Recorder: ViewModifier, @preconcurrency Animatable {
        let log: DiagLog
        let isActive: Bool
        var progress: Double

        var animatableData: Double {
            get { progress }
            set { progress = newValue }
        }

        func body(content: Content) -> some View {
            if isActive { log.activeBuilt += 1 }
            if progress > 0, progress < 1 { log.inBetween += 1 }
            if !isActive, progress < 1 { log.identityBelowOne += 1 }
            let log = log
            let isActive = isActive
            return content
                .opacity(progress)
                .transaction { transaction in
                    guard transaction.animation != nil else { return }
                    MainActor.assumeIsolated {
                        log.anyAnimated += 1
                        if isActive { log.activeAnimated += 1 }
                    }
                }
        }
    }
}

@available(iOS 17, tvOS 17, macOS 14, visionOS 1, *)
private struct Probe: CustomAnimation, Hashable {
    nonisolated(unsafe) let log: DiagLog

    nonisolated func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        MainActor.assumeIsolated { log.customAnimationCalls += 1 }
        return time < 0.05 ? value.scaled(by: time / 0.05) : nil
    }

    nonisolated static func == (lhs: Probe, rhs: Probe) -> Bool { lhs.log === rhs.log }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(log)) }
}

extension View {
    @MainActor
    fileprivate func recordingAnimatedTransactions(_ log: DiagLog) -> some View {
        transaction { transaction in
            guard transaction.animation != nil else { return }
            MainActor.assumeIsolated { log.outerAnimated += 1 }
        }
    }
}

@MainActor
private final class Flag: ObservableObject {
    @Published var value = false
}

private struct Plain: View {
    @ObservedObject var flag: Flag
    let log: DiagLog

    var body: some View {
        ZStack {
            if flag.value {
                SwiftUI.Color.red.transition(log.transition)
            }
        }
    }
}

@Suite(.serialized, .timeLimit(.minutes(5))) @MainActor
struct TransitionFrameDiagnostics {
    @Test func report() async {
        var lines: [String] = []

#if os(macOS)
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let view = NSView(frame: frame)
        window.contentView = view
        window.orderFront(nil)
        let ticker = Ticker()
        let link = view.displayLink(target: ticker, selector: #selector(Ticker.tick(_:)))
        link.add(to: .main, forMode: .common)
        try? await Task.sleep(for: .seconds(1))
        link.invalidate()
        lines.append("env reduceMotion=\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) screens=\(NSScreen.screens.count) windowScreen=\(window.screen != nil) visible=\(window.isVisible) occlusionVisible=\(window.occlusionState.contains(.visible)) ticksIn1s=\(ticker.count) nsApp=\(NSApp != nil) appActive=\(NSApp?.isActive ?? false)")
        window.orderOut(nil)
#endif

        // Plain SwiftUI, no Nuke.
        do {
            let log = DiagLog()
            let flag = Flag()
            let host = ViewHost(0) { _ in Plain(flag: flag, log: log).recordingAnimatedTransactions(log) }
            await host.render()
            withAnimation(log.animation) { flag.value = true }
            await host.render()
            await host.render()
            lines.append("plain animated: \(log.text)")
        }
        do {
            let log = DiagLog()
            let flag = Flag()
            let host = ViewHost(0) { _ in
                Plain(flag: flag, log: log)
                    .recordingAnimatedTransactions(log)
                    .environment(\._accessibilityReduceMotion, false)
            }
            await host.render()
            withAnimation(log.animation) { flag.value = true }
            await host.render()
            await host.render()
            lines.append("plain animated, reduce motion pinned off: \(log.text)")
        }
        do {
            let log = DiagLog()
            let flag = Flag()
            let host = ViewHost(0) { _ in Plain(flag: flag, log: log).recordingAnimatedTransactions(log) }
            await host.render()
            flag.value = true
            await host.render()
            lines.append("plain no animation: \(log.text)")
        }

        // LazyImage, in the two cases that decide it.
        do {
            let log = DiagLog()
            let pipeline = makePipeline()
            let host = ViewHost(Test.url) { url in
                LazyImage(url: url).pipeline(pipeline).imageTransition(log.transition, animation: log.animation).recordingAnimatedTransactions(log)
            }
            await host.render()
            await host.render()
            lines.append("lazy download: \(log.text)")
        }
        do {
            let log = DiagLog()
            let pipeline = makePipeline()
            pipeline.cache[ImageRequest(url: Test.url)] = Test.container
            let host = ViewHost(Test.url) { url in
                LazyImage(url: url).pipeline(pipeline).imageTransition(log.transition, animation: log.animation).recordingAnimatedTransactions(log)
            }
            await host.render()
            await host.render()
            lines.append("lazy memory hit: \(log.text)")
        }

        let summary = lines.joined(separator: " | ")
        print("◇ DIAG \(summary)")
#if os(macOS)
        Issue.record(Comment(rawValue: "DIAG \(summary)"))
#endif
    }

    private func makePipeline() -> ImagePipeline {
        let dataLoader = MockDataLoader()
        return ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = MockImageCache()
            $0.dataCache = MockDataCache()
        }
    }
}

#endif
