// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI
import UIKit

/// Demonstrates ``ImagePrefetcher`` in UIKit and in SwiftUI.
///
/// ```swift
/// prefetcher.startPrefetching(with: urls)
/// prefetcher.stopPrefetching(with: urls)
/// ```
struct PrefetchingDemo: View {
    private enum Kind: String, CaseIterable, Identifiable {
        case uikit = "UIKit"
        case swiftUI = "SwiftUI"

        var id: Self { self }
    }

    @State private var kind: Kind = .uikit

    var body: some View {
        VStack(spacing: 0) {
            Picker("Kind", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(16)

            switch kind {
            case .uikit:
                ViewControllerView { PrefetchingViewController() }
            case .swiftUI:
                SwiftUIPrefetchingDemo()
            }
        }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Prefetching",
        "`ImagePrefetcher` downloads images before they appear on screen. It runs the requests at a low priority and limits how many are in flight, so it never gets in the way of the images the user is actually looking at.",
        code: """
        prefetcher.startPrefetching(with: urls)
        prefetcher.stopPrefetching(with: urls)
        """,
        points: [
            .init("Same request", "Prefetch with the request you display with. If they differ by so much as a processor, the prefetcher fills the cache with images you never show."),
            .init("UIKit", "`UICollectionViewDataSourcePrefetching` tells you exactly which items to start and which ones to stop."),
            .init("SwiftUI", "There is no equivalent, so the demo derives the window from `onAppear` and `onDisappear`."),
            .init("Pausing", "`isPaused` holds the queue when the screen goes away. The outstanding requests finish and the rest wait, so coming back is instant."),
            .init("Destination", "Prefetch into the memory cache for images that are about to be shown, or into the disk cache for ones that might be.")
        ]
    )
}

// MARK: - UIKit

/// Uses `UICollectionViewDataSourcePrefetching`, which tells you exactly which
/// items to prefetch and which ones are no longer needed.
private final class PrefetchingViewController: PhotoGridViewController, UICollectionViewDataSourcePrefetching {
    private let prefetcher = ImagePrefetcher()
    private let logView = PrefetchLogView()

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView.isPrefetchingEnabled = true
        collectionView.prefetchDataSource = self

        logView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logView)
        NSLayoutConstraint.activate([
            logView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            logView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            logView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        prefetcher.isPaused = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // The prefetcher finishes the outstanding requests and holds the rest,
        // so the work resumes instantly when the user comes back.
        prefetcher.isPaused = true
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        prefetcher.startPrefetching(with: indexPaths.map { photos[$0.item] })
        logView.append("start", indexPaths.map(\.item))
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        prefetcher.stopPrefetching(with: indexPaths.map { photos[$0.item] })
        logView.append("stop", indexPaths.map(\.item))
    }
}

/// Shows the last few prefetch calls at the bottom of the screen.
private final class PrefetchLogView: UIView {
    private let label = UILabel()
    private var lines: [String] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)

        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 3
        label.text = "Scroll to see the prefetcher at work"

        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func append(_ action: String, _ indices: [Int]) {
        guard !indices.isEmpty else { return }
        lines.insert("\(action) \(indices.sorted().map(String.init).joined(separator: " "))", at: 0)
        lines = Array(lines.prefix(3))
        label.text = lines.joined(separator: "\n")
    }
}

// MARK: - SwiftUI

private struct SwiftUIPrefetchingDemo: View {
    @StateObject private var model = SwiftUIPrefetchingModel()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(Array(model.photos.enumerated()), id: \.offset) { index, url in
                        SquareCell {
                            LazyImage(url: url) { state in
                                if let image = state.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Color(.secondarySystemBackground)
                                }
                            }
                        }
                        .onAppear { model.prefetcher.onAppear(index) }
                        .onDisappear { model.prefetcher.onDisappear(index) }
                    }
                }
            }

            Text(model.status)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
        }
        .onDisappear { model.prefetcher.isPaused = true }
        .onAppear { model.prefetcher.isPaused = false }
    }
}

@MainActor
private final class SwiftUIPrefetchingModel: ObservableObject {
    let photos = DemoImages.photos
    let prefetcher: GridPrefetcher

    @Published private(set) var status = "Scroll to see the prefetcher at work"

    init() {
        prefetcher = GridPrefetcher(urls: photos)
        prefetcher.onChange = { [weak self] started, stopped in
            var components: [String] = []
            if let first = started.first, let last = started.last {
                components.append("start \(first)–\(last)")
            }
            if let first = stopped.first, let last = stopped.last {
                components.append("stop \(first)–\(last)")
            }
            self?.status = components.joined(separator: "   ")
        }
    }
}
