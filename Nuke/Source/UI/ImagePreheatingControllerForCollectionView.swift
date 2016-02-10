// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import UIKit

public class ImagePreheatingControllerForCollectionView: ImagePreheatingController {
    public var collectionView: UICollectionView {
        return self.scrollView as! UICollectionView
    }
    public var collectionViewLayout: UICollectionViewFlowLayout {
        return self.collectionView.collectionViewLayout as! UICollectionViewFlowLayout
    }
    
    /** The proportion of the collection view size (either width or height depending on the scroll axis) used as a preheat window.
    */
    public var preheatRectRatio: CGFloat = 1.0
    
    /** Determines how far the user needs to refresh preheat window.
    */
    public var preheatRectUpdateRatio: CGFloat = 0.33
    
    private var previousContentOffset = CGPointZero
    
    public init(collectionView: UICollectionView) {
        assert(collectionView.collectionViewLayout is UICollectionViewFlowLayout)
        super.init(scrollView: collectionView)
    }
    
    public override var enabled: Bool {
        didSet {
            if self.enabled {
                self.updatePreheatRect()
            } else {
                self.previousContentOffset = CGPointZero
                self.updatePreheatIndexPaths([])
            }
        }
    }
    
    public override func scrollViewDidScroll() {
        if self.enabled {
            self.updatePreheatRect()
        }
    }

    private func updatePreheatRect() {
        let scrollAxis = self.collectionViewLayout.scrollDirection
        let updateMargin = (scrollAxis == .Vertical ? CGRectGetHeight : CGRectGetWidth)(self.collectionView.bounds) * self.preheatRectUpdateRatio
        let contentOffset = self.collectionView.contentOffset
        guard distanceBetweenPoints(contentOffset, self.previousContentOffset) > updateMargin || self.previousContentOffset == CGPointZero else {
            return
        }
        // Update preheat window
        let scrollDirection: ScrollDirection = ((scrollAxis == .Vertical ? contentOffset.y >= self.previousContentOffset.y : contentOffset.x >= self.previousContentOffset.x) || self.previousContentOffset == CGPointZero) ? .Forward : .Backward
        
        self.previousContentOffset = contentOffset
        let preheatRect = self.preheatRectInScrollDirection(scrollDirection)
        let preheatIndexPaths = self.indexPathsForElementsInRect(preheatRect).subtract(self.collectionView.indexPathsForVisibleItems())
        self.updatePreheatIndexPaths(sortIndexPaths(preheatIndexPaths, inScrollDirection: scrollDirection))
    }
    
    private func preheatRectInScrollDirection(direction: ScrollDirection) -> CGRect {
        let viewport = CGRect(origin: self.collectionView.contentOffset, size: self.collectionView.bounds.size)
        switch self.collectionViewLayout.scrollDirection {
        case .Vertical:
            let height = CGRectGetHeight(viewport) * self.preheatRectRatio
            let y = (direction == .Forward) ? CGRectGetMaxY(viewport) : CGRectGetMinY(viewport) - height
            return CGRectIntegral(CGRect(x: 0, y: y, width: CGRectGetWidth(viewport), height: height))
        case .Horizontal:
            let width = CGRectGetWidth(viewport) * self.preheatRectRatio
            let x = (direction == .Forward) ? CGRectGetMaxX(viewport) : CGRectGetMinX(viewport) - width
            return CGRectIntegral(CGRect(x: x, y: 0, width: width, height: CGRectGetHeight(viewport)))
        }
    }
    
    private func indexPathsForElementsInRect(rect: CGRect) -> Set<NSIndexPath> {
        guard let layoutAttributes = self.collectionViewLayout.layoutAttributesForElementsInRect(rect) else {
            return []
        }
        return Set(layoutAttributes.filter{ return $0.representedElementCategory == .Cell }.map{ return $0.indexPath })
    }
}
