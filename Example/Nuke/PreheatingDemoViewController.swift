//
//  PreheatingDemoViewController.swift
//  Nuke
//
//  Copyright (c) 2016 Alexander Grebenyuk (github.com/kean). All rights reserved.
//

import UIKit
import Nuke
import Preheat

private let cellReuseID = "reuseID"

class PreheatingDemoViewController: UICollectionViewController {
    var photos: [NSURL]!
    var preheatController: PreheatController<UICollectionView>!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        photos = demoPhotosURLs
        preheatController = PreheatController(view: collectionView!)
        preheatController.handler = { [weak self] in
            self?.preheatWindowChanged(addedIndexPaths: $0, removedIndexPaths: $1)
        }
        
        collectionView?.backgroundColor = UIColor.whiteColor()
        collectionView?.registerClass(UICollectionViewCell.self, forCellWithReuseIdentifier: cellReuseID)
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        updateItemSize()
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        preheatController.enabled = true
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        
        preheatController.enabled = false
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
    
    override func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return photos.count
    }
    
    override func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier(cellReuseID, forIndexPath: indexPath)
        cell.backgroundColor = UIColor(white: 235.0 / 255.0, alpha: 1.0)
        
        let imageView = imageViewForCell(cell)
        let imageURL = photos[indexPath.row]
        imageView.image = nil
        imageView.nk_setImageWith(imageRequestWithURL(imageURL))
        
        return cell
    }
    
    func imageRequestWithURL(URL: NSURL) -> ImageRequest {
        func imageTargetSize() -> CGSize {
            let size = (collectionViewLayout as! UICollectionViewFlowLayout).itemSize
            let scale = UIScreen.mainScreen().scale
            return CGSize(width: size.width * scale, height: size.height * scale)
        }
        return ImageRequest(URL: URL, targetSize: imageTargetSize(), contentMode: .AspectFill)
    }
    
    override func collectionView(collectionView: UICollectionView, didEndDisplayingCell cell: UICollectionViewCell, forItemAtIndexPath indexPath: NSIndexPath) {
        imageViewForCell(cell).nk_cancelLoading()
    }
    
    func imageViewForCell(cell: UICollectionViewCell) -> UIImageView {
        var imageView = cell.viewWithTag(15) as? UIImageView
        if imageView == nil {
            imageView = UIImageView(frame: cell.bounds)
            imageView!.autoresizingMask =  [.FlexibleWidth, .FlexibleHeight]
            imageView!.tag = 15
            imageView!.contentMode = .ScaleAspectFill
            imageView!.clipsToBounds = true
            cell.addSubview(imageView!)
        }
        return imageView!
    }
    
    // MARK: Preheating
 
    func preheatWindowChanged(addedIndexPaths addedIndexPaths: [NSIndexPath], removedIndexPaths: [NSIndexPath]) {
        func requestForIndexPaths(indexPaths: [NSIndexPath]) -> [ImageRequest] {
            return indexPaths.map { imageRequestWithURL(photos[$0.row]) }
        }
        Nuke.startPreheatingImages(requestForIndexPaths(addedIndexPaths))
        Nuke.stopPreheatingImages(requestForIndexPaths(removedIndexPaths))
        logAddedIndexPaths(addedIndexPaths, removedIndexPaths: removedIndexPaths)
    }
    
    func logAddedIndexPaths(addedIndexPath: [NSIndexPath], removedIndexPaths: [NSIndexPath]) {
        func stringForIndexPaths(indexPaths: [NSIndexPath]) -> String {
            guard indexPaths.count > 0 else {
                return "[]"
            }
            let items = indexPaths.map{ return "\($0.item)" }.joinWithSeparator(" ")
            return "[\(items)]"
        }
        print("did change preheat rect with added indexes \(stringForIndexPaths(addedIndexPath)), removed indexes \(stringForIndexPaths(removedIndexPaths))")
    }
}
