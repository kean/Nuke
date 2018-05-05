// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke

private let cellReuseID = "reuseID"

final class RateLimiterDemoViewController: UICollectionViewController {
    var photos: [URL]!

    var itemsPerRow = 10

    var pipeline: ImagePipeline!

    override func viewDidLoad() {
        super.viewDidLoad()

        pipeline = ImagePipeline {
            let urlSessionConf = URLSessionConfiguration.default
            urlSessionConf.urlCache = nil // disable disk cache
            $0.dataLoader = DataLoader(configuration: urlSessionConf)

            $0.imageCache = nil // disable memory cache

            $0.isDeduplicationEnabled = false // disable deduplication
        }

        photos = demoPhotosURLs
        for _ in 0..<10 {
            self.photos.append(contentsOf: self.photos)
        }
        
        collectionView?.backgroundColor = UIColor.white
        collectionView?.register(UICollectionViewCell.self, forCellWithReuseIdentifier: cellReuseID)
        if #available(iOS 10.0, *) {
            collectionView?.isPrefetchingEnabled = false
        }
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
        
        let imageView = imageViewForCell(cell)

        var options = ImageLoadingOptions()
        options.pipeline = pipeline

        Nuke.loadImage(
            with: ImageRequest(url: photos[indexPath.row], targetSize: ImageDecompressor.targetSize(for: imageView), contentMode: .aspectFill),
            options: options,
            into: imageView
        )
        
        return cell
    }
    
    func imageViewForCell(_ cell: UICollectionViewCell) -> UIImageView {
        var imageView: UIImageView! = cell.viewWithTag(15) as? UIImageView
        if imageView == nil {
            imageView = UIImageView(frame: cell.bounds)
            imageView.autoresizingMask =  [.flexibleWidth, .flexibleHeight]
            imageView.tag = 15
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            cell.addSubview(imageView!)
        }
        return imageView!
    }
}
