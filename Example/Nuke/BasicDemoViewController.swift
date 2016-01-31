//
//  BasicDemoViewController.swift
//  Nuke
//
//  Copyright (c) 2016 Alexander Grebenyuk (github.com/kean). All rights reserved.
//

import UIKit
import Nuke

private let cellReuseID = "reuseID"

class BasicDemoViewController: UICollectionViewController {
    var photos: [NSURL]!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.photos = demoPhotosURLs
        
        self.collectionView?.backgroundColor = UIColor.whiteColor()
        self.collectionView?.registerClass(UICollectionViewCell.self, forCellWithReuseIdentifier: cellReuseID)
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        self.updateItemSize()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.updateItemSize()
    }
    
    func updateItemSize() {
        let layout = self.collectionViewLayout as! UICollectionViewFlowLayout
        layout.minimumLineSpacing = 2.0
        layout.minimumInteritemSpacing = 2.0
        let itemsPerRow = 4
        let side = (Double(self.view.bounds.size.width) - Double(itemsPerRow - 1) * 2.0) / Double(itemsPerRow)
        layout.itemSize = CGSize(width: side, height: side)
    }
    
    // MARK: UICollectionView
    
    override func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.photos.count
    }
    
    override func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier(cellReuseID, forIndexPath: indexPath)
        cell.backgroundColor = UIColor(white: 235.0 / 255.0, alpha: 1.0)
        
        let imageView = self.imageViewForCell(cell)
        imageView.image = nil
        let imageURL = self.photos[indexPath.row]
        imageView.nk_setImageWith(imageURL)
        
        return cell
    }
    
    override func collectionView(collectionView: UICollectionView, didEndDisplayingCell cell: UICollectionViewCell, forItemAtIndexPath indexPath: NSIndexPath) {
        self.imageViewForCell(cell).nk_cancelLoading()
    }
    
    func imageViewForCell(cell: UICollectionViewCell) -> UIImageView {
        var imageView: UIImageView! = cell.viewWithTag(15) as? UIImageView
        if imageView == nil {
            imageView = UIImageView(frame: cell.bounds)
            imageView.autoresizingMask =  [.FlexibleWidth, .FlexibleHeight]
            imageView.tag = 15
            imageView.contentMode = .ScaleAspectFill
            imageView.clipsToBounds = true
            cell.addSubview(imageView!)
        }
        return imageView!
    }
}
