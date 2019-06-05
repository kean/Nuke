// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke

private let cellReuseID = "reuseID"
private var loggingEnabled = false

final class PrefetchingDemoViewController: BasicDemoViewController, UICollectionViewDataSourcePrefetching {

    let preheater = ImagePreheater()

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView?.isPrefetchingEnabled = true
        collectionView?.prefetchDataSource = self
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
