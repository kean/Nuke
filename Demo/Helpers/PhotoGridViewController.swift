// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import UIKit

/// A grid of photos that loads images into `UIImageView` using the
/// `loadImage(with:options:into:)` extension from NukeUI.
///
/// The screens that demonstrate prefetching and the behavior of the pipeline
/// under stress subclass it and change the pipeline or the requests.
///
/// ```swift
/// func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
///     let cell = ...
///     // Any previous request for this image view is cancelled automatically.
///     loadImage(with: photos[indexPath.item], into: cell.imageView)
///     return cell
/// }
/// ```
class PhotoGridViewController: UICollectionViewController {
    var photos: [URL] = DemoImages.photos
    var pipeline: ImagePipeline = .shared
    var itemsPerRow = 4

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
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseID)
    }

    // Before the layout pass rather than after it: the collection view lays
    // out, and dequeues, its first cells in that pass, and a cell asks for an
    // image of the size it has then. Sized afterwards, the first screenful
    // would ask for the flow layout's default 50 pt and never ask again.
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        guard let layout = collectionViewLayout as? UICollectionViewFlowLayout, view.bounds.width > 0 else { return }
        let spacing: CGFloat = 2
        let side = ((view.bounds.width - CGFloat(itemsPerRow - 1) * spacing) / CGFloat(itemsPerRow)).rounded(.down)
        let itemSize = CGSize(width: side, height: side)
        // It runs before every layout pass: the layout changes only with the width.
        guard layout.itemSize != itemSize else { return }
        layout.minimumLineSpacing = spacing
        layout.minimumInteritemSpacing = spacing
        layout.itemSize = itemSize
    }

    /// Override to change the request, e.g. to add processors.
    func makeRequest(for url: URL, size: CGSize) -> ImageRequest {
        ImageRequest(url: url)
    }

    /// Override to change how the image is displayed.
    func makeLoadingOptions() -> ImageLoadingOptions {
        var options = ImageLoadingOptions.shared
        options.pipeline = pipeline
        return options
    }

    // MARK: UICollectionViewDataSource

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        photos.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoCell.reuseID, for: indexPath) as! PhotoCell
        let request = makeRequest(for: photos[indexPath.item], size: cell.bounds.size)
        // Nuke prepares the view for reuse: the request that the cell had
        // before this one is cancelled and the previous image is removed.
        loadImage(with: request, options: makeLoadingOptions(), into: cell.imageView)
        return cell
    }
}

final class PhotoCell: UICollectionViewCell {
    static let reuseID = "PhotoCell"

    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .secondarySystemBackground

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
