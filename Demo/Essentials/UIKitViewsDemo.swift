// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI
import UIKit

/// Demonstrates the two ways to load images in UIKit, one grid on each side of
/// a picker: the `loadImage(with:options:into:)` extension on a plain
/// `UIImageView`, and ``LazyImageView`` – the UIKit and AppKit counterpart of
/// ``LazyImage``.
///
/// The difference is who owns the loading states. With the extension, you do:
/// the placeholder, the failure image, and the transition come with every call.
/// `LazyImageView` owns them, so a cell sets them once.
struct UIKitViewsDemo: View {
    private enum Kind: String, CaseIterable, Identifiable {
        case imageView = "UIImageView"
        case lazyImageView = "LazyImageView"

        var id: Self { self }

        var caption: LocalizedStringKey {
            switch self {
            case .imageView: "You own the states: every call passes the placeholder, failure image, and transition in `ImageLoadingOptions`."
            case .lazyImageView: "The view owns the states: it shows its own placeholder and failure views, and reports the result in `onCompletion`."
            }
        }
    }

    @State private var kind: Kind = .imageView

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("View", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Text(kind.caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            // Only the selected grid exists. The other one is released, and its
            // image views cancel whatever they were still loading as they go.
            switch kind {
            case .imageView:
                ViewControllerView { ImageViewGridViewController() }
            case .lazyImageView:
                ViewControllerView { LazyImageViewGridViewController() }
            }
        }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "UIKit Views",
        "Two ways to load images in UIKit, one on each side of the picker. `loadImage(with:options:into:)` works with any `UIImageView` and leaves the loading states to you. `LazyImageView`, the UIKit and AppKit counterpart of `LazyImage`, owns them: a cell sets them once and the view takes it from there.",
        code: """
        // You own the states
        loadImage(with: request,
                  options: options,
                  into: cell.imageView)

        // The view owns them
        imageView.placeholderView = spinner
        imageView.failureImage = warningImage
        imageView.url = url
        """,
        points: [
            .init("You own the states", "`ImageLoadingOptions` carries the placeholder, the failure image, the transition, the content modes, and the tint colors. They are images rather than views, and they come with every call unless you set them once on `ImageLoadingOptions.shared`."),
            .init("The view owns them", "`LazyImageView` shows its placeholder and failure view itself. They are real views, so they can animate or show progress, like the spinner here. `onStart`, `onProgress`, `onSuccess`, `onFailure`, and `onCompletion` report the rest."),
            .init("Starting a request", "Every `loadImage` call starts one. Setting `url` on a `LazyImageView` starts one too, and setting `request` does the same with processors, priority, and options attached."),
            .init("Reuse", "Nothing else is needed for cell reuse with either one: a new call, or a new `url`, removes the previous image and cancels the previous request. `reset()` does the same for a `LazyImageView` up front, which is what its cell does before it is used again."),
            .init("Switching", "A request is cancelled when its view goes away. Switching the picker releases the other grid, and with it everything that grid was still loading."),
            .init("Downsampling", "The `UIImageView` cells ask for the image at their own size. A bitmap of the full photo is many times larger, and it is the bitmap that the memory cache holds."),
            .init("Failure", "The first cell of each grid uses a URL that always fails, which is what puts the failure image on screen.")
        ]
    )
}

// MARK: - UIImageView

/// Loads with `loadImage(with:options:into:)`, and passes the placeholder, the
/// failure image, and the transition along with every request.
private final class ImageViewGridViewController: PhotoGridViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        itemsPerRow = 3
        photos = [DemoImages.failing] + DemoImages.photos
    }

    override func makeLoadingOptions() -> ImageLoadingOptions {
        var options = ImageLoadingOptions()
        options.placeholder = UIImage(systemName: "photo")
        options.failureImage = UIImage(systemName: "exclamationmark.triangle")
        options.transition = .fadeIn(duration: 0.33)
        options.contentModes = .init(success: .scaleAspectFill, failure: .center, placeholder: .center)
        options.tintColors = .init(success: nil, failure: .systemRed, placeholder: .tertiaryLabel)
        options.pipeline = pipeline
        return options
    }

    override func makeRequest(for url: URL, size: CGSize) -> ImageRequest {
        // Downsampling the image to the size of the cell keeps the memory
        // cache small: a bitmap of the original photo is many times larger.
        ImageRequest(url: url, processors: [.resize(size: size)])
    }
}

// MARK: - LazyImageView

/// Gives every `LazyImageView` its placeholder, failure image, and transition
/// once, when the cell is created, and after that only a URL.
private final class LazyImageViewGridViewController: UICollectionViewController {
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
