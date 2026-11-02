// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

#if canImport(UIKit) && !os(watchOS)

import Testing
import SwiftUI
import UIKit
import Nuke
import NukeUI

/// The first time a screen of `LazyImage` cells is shown, and every image is in
/// the memory cache. The cost of a cell is what it adds to a plain `Image`, so
/// compare the numbers of one run with each other: they drift with the load of
/// the machine.
///
/// `timeToImage` stops when every cell has built its content with the image.
/// `settled` also waits for the work that follows (`onAppear`, the load, the
/// render it asks for) to run out. `parentUpdate` is what the same screen pays
/// afterwards, every time its parent updates.
@Suite(.serialized, .timeLimit(.minutes(5)))
@MainActor
final class LazyImageFirstShowPerformanceTests {
    private static let cellCount = 100
    private static let parentUpdateCount = 10

    private let requests: [ImageRequest]
    private let image = ImageContainer(image: PlatformImage())

    init() {
        requests = (0..<Self.cellCount).map { ImageRequest(url: URL(string: "http://test.com/first-show/\($0)")!) }
        for request in requests {
            ImagePipeline.shared.cache[request] = image
        }
    }

    // Not isolated: Swift Testing releases the suite off the main actor.
    deinit {
        for request in requests {
            ImagePipeline.shared.cache[request] = nil
        }
    }

    @Test func plainImageSettled() {
        measureFirstShow(.plainImage, until: .settled)
    }

    @Test func lazyImageTimeToImage() {
        measureFirstShow(.lazyImage, until: .timeToImage)
    }

    @Test func lazyImageSettled() {
        measureFirstShow(.lazyImage, until: .settled)
    }

    @Test func lazyImageParentUpdate() {
        let counters = Counters()
        let parent = Parent()
        let screen = Screen(root: ParentView(parent: parent) { self.cells(.lazyImage, counters: counters) }, counters: counters)
        screen.pump(until: { counters.appeared >= Self.cellCount })
        screen.settle()

        counters.reset()
        measure {
            for _ in 0..<Self.parentUpdateCount {
                parent.tick += 1
                screen.pump()
            }
        }
        screen.close()
        report(counters)
    }

    // MARK: - Harness

    private enum Cell { case plainImage, lazyImage }
    private enum Stop { case timeToImage, settled }

    @MainActor
    private final class Counters {
        var bodiesWithImage = 0
        var bodiesWithoutImage = 0
        var appeared = 0

        var activity: Int { bodiesWithImage + bodiesWithoutImage + appeared }

        func reset() {
            bodiesWithImage = 0
            bodiesWithoutImage = 0
            appeared = 0
        }
    }

    /// A parent with state of its own, which rebuilds its content when it changes.
    @MainActor
    private final class Parent: ObservableObject {
        @Published var tick = 0
    }

    private struct ParentView<Content: View>: View {
        @ObservedObject var parent: Parent
        @ViewBuilder let content: () -> Content

        var body: some View {
            let _ = parent.tick
            content()
        }
    }

    private func report(_ counters: Counters, name: String = #function) {
        print("◇ Bodies \(name) withImage=\(counters.bodiesWithImage) withoutImage=\(counters.bodiesWithoutImage)")
    }

    /// A sample gets counters of its own, so that a late callback from the one
    /// before it can't add to them. A sample that stops at the first image also
    /// leaves the rest of its work on the run loop, where the next one would
    /// pay for it, so `setup`, which isn't timed, finishes it first.
    private func measureFirstShow(_ cell: Cell, until stop: Stop, name: String = #function) {
        var previous: Screen?
        measure(name, setup: { () -> Counters in
            previous?.close()
            return Counters()
        }, { counters in
            previous = show(cell, until: stop, counters: counters)
        })
        previous?.close()
        if cell == .lazyImage, let previous {
            report(previous.counters, name: name)
        }
    }

    private func show(_ cell: Cell, until stop: Stop, counters: Counters) -> Screen {
        let screen = Screen(root: cells(cell, counters: counters), counters: counters)
        switch (cell, stop) {
        case (.lazyImage, .timeToImage):
            screen.pump(until: { counters.bodiesWithImage >= Self.cellCount })
        default:
            screen.pump(until: { counters.appeared >= Self.cellCount })
            screen.settle()
        }
        return screen
    }

    private func cells(_ cell: Cell, counters: Counters) -> some View {
        let urls = requests.map(\.url)
        let platformImage = image.image
        return VStack(spacing: 0) {
            ForEach(0..<Self.cellCount, id: \.self) { index in
                switch cell {
                case .plainImage:
                    Image(uiImage: platformImage)
                        .resizable()
                        .frame(width: 10, height: 10)
                        .onAppear { counters.appeared += 1 }
                case .lazyImage:
                    LazyImage(url: urls[index]) { state in
                        if let image = state.image {
                            let _ = counters.bodiesWithImage += 1
                            image.resizable()
                        } else {
                            let _ = counters.bodiesWithoutImage += 1
                            Color.gray
                        }
                    }
                    .frame(width: 10, height: 10)
                    .onAppear { counters.appeared += 1 }
                }
            }
        }
    }

    /// A screen of cells in a window.
    @MainActor
    private final class Screen {
        let counters: Counters
        private let window: UIWindow
        private let view: UIView

        init(root: some View, counters: Counters) {
            self.counters = counters
            let controller = UIHostingController(rootView: root)
            controller.safeAreaRegions = []
            let frame = CGRect(x: 0, y: 0, width: 200, height: 1200)
            controller.view.frame = frame
            view = controller.view
            window = UIWindow(frame: frame)
            window.rootViewController = controller
            window.isHidden = false
            layout()
        }

        private func layout() {
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }

        func pump() {
            layout()
            RunLoop.current.run(mode: .default, before: Date())
        }

        /// Gives up after a while: this runs on the main actor without ever
        /// suspending, so the time limit of the suite can't interrupt it.
        func pump(until condition: () -> Bool) {
            let deadline = ContinuousClock.now + .seconds(10)
            while !condition() {
                guard ContinuousClock.now < deadline else {
                    Issue.record("The cells didn't get there: \(counters.activity) events")
                    return
                }
                pump()
            }
        }

        /// Pumps until nothing has happened for a few turns in a row.
        func settle() {
            var quietTurns = 0
            var activity = -1
            pump(until: {
                quietTurns = counters.activity == activity ? quietTurns + 1 : 0
                activity = counters.activity
                return quietTurns == 5
            })
        }

        func close() {
            settle()
            window.isHidden = true
            settle()
        }
    }
}

#endif
