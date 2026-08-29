// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import Foundation

/// Prefetches a window of images ahead of the visible cells of a SwiftUI grid.
///
/// SwiftUI has no equivalent of `UICollectionViewDataSourcePrefetching`, so the
/// visible range is tracked with `onAppear` and `onDisappear` instead. SwiftUI
/// can report those out of order, hence the small debounce.
@MainActor
final class GridPrefetcher {
    /// Called every time the prefetch window changes.
    var onChange: ((_ started: [Int], _ stopped: [Int]) -> Void)?

    private let prefetcher = ImagePrefetcher()
    private let urls: [URL]
    private let windowSize: Int

    private var visible: Set<Int> = []
    private var previouslyVisible: Set<Int> = []
    private var window: Range<Int> = 0..<0
    private var isUpdateScheduled = false

    init(urls: [URL], windowSize: Int = 16) {
        self.urls = urls
        self.windowSize = windowSize
    }

    func onAppear(_ index: Int) {
        visible.insert(index)
        scheduleUpdate()
    }

    func onDisappear(_ index: Int) {
        visible.remove(index)
        scheduleUpdate()
    }

    /// Pauses the prefetching, e.g. when the screen goes away. The prefetcher
    /// finishes the outstanding requests and holds the rest.
    var isPaused: Bool {
        get { prefetcher.isPaused }
        set { prefetcher.isPaused = newValue }
    }

    private func scheduleUpdate() {
        guard !isUpdateScheduled else { return }
        isUpdateScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self else { return }
            self.isUpdateScheduled = false
            self.updateWindow()
        }
    }

    private func updateWindow() {
        guard let lowest = visible.min(), let highest = visible.max() else { return }

        // Prefetch in the direction the user is scrolling.
        let isScrollingDown = highest >= (previouslyVisible.max() ?? 0)
        previouslyVisible = visible

        if isScrollingDown {
            setWindow((highest + 1)..<(highest + 1 + windowSize))
        } else {
            setWindow(max(0, lowest - windowSize)..<lowest)
        }
    }

    private func setWindow(_ newWindow: Range<Int>) {
        let valid = Set(urls.indices)
        let old = Set(window).intersection(valid)
        let new = Set(newWindow).intersection(valid)
        window = newWindow

        let started = new.subtracting(old).sorted()
        let stopped = old.subtracting(new).sorted()
        guard !started.isEmpty || !stopped.isEmpty else { return }

        prefetcher.startPrefetching(with: started.map { urls[$0] })
        prefetcher.stopPrefetching(with: stopped.map { urls[$0] })
        onChange?(started, stopped)
    }
}
