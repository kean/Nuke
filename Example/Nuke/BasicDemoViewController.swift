//
//  BasicDemoViewController.swift
//  Nuke
//
//  Created by kean on 09/13/2015.
//  Copyright (c) 2015 kean. All rights reserved.
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
        imageView.prepareForReuse()
        let imageURL = self.photos[indexPath.row]
        imageView.setImageWithURL(imageURL)
        
        return cell
    }
    
    override func collectionView(collectionView: UICollectionView, didEndDisplayingCell cell: UICollectionViewCell, forItemAtIndexPath indexPath: NSIndexPath) {
        self.imageViewForCell(cell).prepareForReuse()
    }
    
    func imageViewForCell(cell: UICollectionViewCell) -> Nuke.ImageView {
        var imageView = cell.viewWithTag(15) as? Nuke.ImageView
        if imageView == nil {
            imageView = Nuke.ImageView(frame: cell.bounds)
            imageView!.autoresizingMask =  [.FlexibleWidth, .FlexibleHeight]
            imageView!.tag = 15
            cell.addSubview(imageView!)
        }
        return imageView!
    }
}
