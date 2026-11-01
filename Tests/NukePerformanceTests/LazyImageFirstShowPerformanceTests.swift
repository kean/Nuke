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
/// render it asks for) to run out.
@Suite(.serialized)
@MainActor
final class LazyImageFirstShowPerformanceTests {
    private static let cellCount = 100

    private let requests: [ImageRequest]
    private let image = ImageContainer(image: PlatformImage())

    init() {
        requests = (0..<Self.cellCount).map { ImageRequest(url: URL(string: "http://test.com/first-show/\($0)")!) }
        for request in requests {
            ImagePipeline.shared.cache[request] = image
        }
    }

    deinit {
        MainActor.assumeIsolated {
            for request in requests {
                ImagePipeline.shared.cache[request] = nil
            }
        }
    }

    @Test func plainImageSettled() {
        measure { show(.plainImage, until: .settled) }
    }

    @Test func lazyImageTimeToImage() {
        let counters = Counters()
        measure(setup: { counters.reset() }) { _ in show(.lazyImage, until: .timeToImage, counters: counters) }
        report(counters)
    }

    @Test func lazyImageSettled() {
        let counters = Counters()
        measure(setup: { counters.reset() }) { _ in show(.lazyImage, until: .settled, counters: counters) }
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

        func reset() {
            bodiesWithImage = 0
            bodiesWithoutImage = 0
            appeared = 0
        }
    }

    private func report(_ counters: Counters, name: String = #function) {
        print("◇ Bodies \(name) withImage=\(counters.bodiesWithImage) withoutImage=\(counters.bodiesWithoutImage)")
    }

    private func show(_ cell: Cell, until stop: Stop, counters: Counters = Counters()) -> Int {
        let requests = requests
        let platformImage = image.image
        let count = Self.cellCount
        let root = VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                switch cell {
                case .plainImage:
                    Image(uiImage: platformImage)
                        .resizable()
                        .frame(width: 10, height: 10)
                        .onAppear { counters.appeared += 1 }
                case .lazyImage:
                    LazyImage(request: requests[index]) { state in
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
        let controller = UIHostingController(rootView: root)
        controller.safeAreaRegions = []
        let frame = CGRect(x: 0, y: 0, width: 200, height: 1200)
        controller.view.frame = frame
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        func pump() {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            RunLoop.current.run(mode: .default, before: Date())
        }

        switch (cell, stop) {
        case (.lazyImage, .timeToImage):
            while counters.bodiesWithImage < count { pump() }
        default:
            while counters.appeared < count { pump() }
            // Work that follows the appearance: the load, the render it asks
            // for. A few quiet turns in a row mean it has run out.
            for _ in 0..<5 { pump() }
        }
        return counters.bodiesWithImage + counters.bodiesWithoutImage
    }
}

#endif
