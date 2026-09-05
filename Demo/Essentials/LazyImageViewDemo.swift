// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI
import UIKit

/// Demonstrates ``LazyImageView`` – the UIKit and AppKit counterpart of
/// ``LazyImage``. Unlike the `UIImageView` extensions, it manages the
/// placeholder and failure views for you.
struct LazyImageViewDemo: View {
    var body: some View {
        ViewControllerView { LazyImageViewDemoViewController() }
            .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "LazyImageView",
        "`LazyImageView` is the UIKit and AppKit counterpart of `LazyImage`. Unlike the `UIImageView` extensions, it owns the placeholder and the failure view, so there is nothing to wire up for the loading states.",
        code: """
        let imageView = LazyImageView()
        imageView.placeholderView = spinner
        imageView.failureImage = warningImage
        imageView.url = url
        """,
        points: [
            .init("Starting a request", "Setting `url` starts one. Setting `request` does the same with processors, priority, and options attached."),
            .init("Reuse", "`reset()` cancels the request and clears the view, which is what a cell does before it is used again. Setting a new `url` does the same thing on its own."),
            .init("Views, not images", "The placeholder and the failure view are real views, so they can animate or show progress."),
            .init("Failure", "The first cell uses a URL that always fails.")
        ]
    )
}

private final class LazyImageViewDemoViewController: UICollectionViewController {
    private let photos = [DemoImages.failing] + DemoImages.photos

    init() {
        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView.backgroundColor = .systemBackground
        collectionView.register(LazyImageViewCell.self, forCellWithReuseIdentifier: "cell")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard let layout = collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let side = ((view.bounds.width - 2) / 2).rounded(.down)
        layout.minimumLineSpacing = 2
        layout.minimumInteritemSpacing = 2
        layout.itemSize = CGSize(width: side, height: side)
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        photos.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! LazyImageViewCell
        cell.imageView.url = photos[indexPath.item]
        return cell
    }
}

private final class LazyImageViewCell: UICollectionViewCell {
    let imageView = LazyImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .secondarySystemBackground

        imageView.placeholderView = UIActivityIndicatorView(style: .medium)
        imageView.placeholderViewPosition = .center
        imageView.failureImage = UIImage(systemName: "exclamationmark.triangle")
        imageView.failureViewPosition = .center
        imageView.transition = .fadeIn(duration: 0.33)
        imageView.imageView.contentMode = .scaleAspectFill
        imageView.imageView.clipsToBounds = true

        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        // Cancels the outstanding request and clears the displayed image.
        imageView.reset()
    }
}
