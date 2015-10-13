// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation
import UIKit

public class ImagePreheatingControllerForCollectionView: ImagePreheatingController {
    public let collectionView: UICollectionView
    public var collectionViewLayout: UICollectionViewFlowLayout {
        return self.collectionView.collectionViewLayout as! UICollectionViewFlowLayout
    }
    
    /** The proportion of the collection view size (either width or height depending on the scroll axis) used as a preheat window.
    */
    public var preheatRectRatio: CGFloat = 1.0
    
    /** Determines how far the user needs to refresh preheat window..
    */
    public var preheatRectUpdateRatio: CGFloat = 0.33
    
    private var previousContentOffset = CGPointZero
    
    public init(collectionView: UICollectionView) {
        assert(collectionView.collectionViewLayout is UICollectionViewFlowLayout)
        self.collectionView = collectionView
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
    
    private enum ScrollDirection {
        case Forward, Backward
    }
    
    private func updatePreheatRect() {
        let scrollAxis = self.collectionViewLayout.scrollDirection
        let updateMargin = (scrollAxis == .Vertical ? CGRectGetHeight : CGRectGetWidth)(self.collectionView.bounds) * self.preheatRectUpdateRatio
        let contentOffset = self.collectionView.contentOffset
        guard distanceBetweenPoints(contentOffset, self.previousContentOffset) > updateMargin || self.previousContentOffset == CGPointZero else {
            return
        }
        let scrollDirection: ScrollDirection = ((scrollAxis == .Vertical ? contentOffset.y >= self.previousContentOffset.y : contentOffset.x >= self.previousContentOffset.x) || self.previousContentOffset == CGPointZero) ? .Forward : .Backward
        
        self.previousContentOffset = contentOffset
        let preheatRect = self.preheatRectInScrollDirection(scrollDirection)
        let visibleIndexPaths = self.collectionView.indexPathsForVisibleItems()
        let preheatIndexPaths = self.indexPathsForElementsInRect(preheatRect).subtract(visibleIndexPaths).sort {
            switch scrollDirection {
            case .Forward: return $0.section < $1.section || $0.item < $1.item
            case .Backward: return $0.section > $1.section || $0.item > $1.item
            }
        }
        self.updatePreheatIndexPaths(preheatIndexPaths)
    }
    
    private func preheatRectInScrollDirection(direction: ScrollDirection) -> CGRect {
        // UIScrollView bounds works differently from UIView bounds, it adds contentOffset
        let viewport = self.collectionView.bounds
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
