// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke

private let cellReuseID = "reuseID"
private var loggingEnabled = false

final class PrefetchingDemoViewController: UICollectionViewController, UICollectionViewDataSourcePrefetching {
    var photos: [URL]!

    let preheater = ImagePreheater()

    override func viewDidLoad() {
        super.viewDidLoad()

        photos = demoPhotosURLs

        collectionView?.backgroundColor = UIColor.white
        if #available(iOS 10.0, *) {
            collectionView?.isPrefetchingEnabled = true
            collectionView?.prefetchDataSource = self
        }
        collectionView?.register(UICollectionViewCell.self, forCellWithReuseIdentifier: cellReuseID)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateItemSize()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateItemSize()
    }

    func updateItemSize() {
        let layout = collectionViewLayout as! UICollectionViewFlowLayout
        layout.minimumLineSpacing = 2.0
        layout.minimumInteritemSpacing = 2.0
        let itemsPerRow = 4
        let side = (Double(view.bounds.size.width) - Double(itemsPerRow - 1) * 2.0) / Double(itemsPerRow)
        layout.itemSize = CGSize(width: side, height: side)
    }

    // MARK: UICollectionView

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return photos.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseID, for: indexPath)
        cell.backgroundColor = UIColor(white: 235.0 / 255.0, alpha: 1.0)

        let imageView = self.imageView(for: cell)
        let imageURL = photos[indexPath.row]

        Nuke.loadImage(
            with: imageURL,
            options: ImageLoadingOptions(transition: .fadeIn(duration: 0.33)),
            into: imageView
        )

        return cell
    }

    func imageView(for cell: UICollectionViewCell) -> UIImageView {
        var imageView = cell.viewWithTag(15) as? UIImageView
        if imageView == nil {
            imageView = UIImageView(frame: cell.bounds)
            imageView!.autoresizingMask =  [.flexibleWidth, .flexibleHeight]
            imageView!.tag = 15
            imageView!.contentMode = .scaleAspectFill
            imageView!.clipsToBounds = true
            cell.addSubview(imageView!)
        }
        return imageView!
    }

    // MARK: UICollectionViewDataSourcePrefetching

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.map { photos[$0.row] }
        preheater.startPreheating(with: urls)
        if loggingEnabled {
            print("prefetchItemsAt: \(stringForIndexPaths(indexPaths))")
        }
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.map { photos[$0.row] }
        preheater.stopPreheating(with: urls)
        if loggingEnabled {
            print("cancelPrefetchingForItemsAt: \(stringForIndexPaths(indexPaths))")
        }
    }
}

private func stringForIndexPaths(_ indexPaths: [IndexPath]) -> String {
    guard indexPaths.count > 0 else {
        return "[]"
    }
    let items = indexPaths
        .map { return "\(($0 as NSIndexPath).item)" }
        .joined(separator: " ")
    return "[\(items)]"
}
