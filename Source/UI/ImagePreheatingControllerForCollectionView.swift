// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import UIKit

/// Preheating controller for `UICollectionView` with `UICollectionViewFlowLayout` layout.
public class ImagePreheatingControllerForCollectionView: ImagePreheatingController {
    /// The collection view that the receiver was initialized with.
    public var collectionView: UICollectionView {
        return scrollView as! UICollectionView
    }
    /// The layout of the collection view.
    public var collectionViewLayout: UICollectionViewFlowLayout {
        return collectionView.collectionViewLayout as! UICollectionViewFlowLayout
    }
    
    /// The proportion of the collection view size (either width or height depending on the scroll axis) used as a preheat window.
    public var preheatRectRatio: CGFloat = 1.0
    
    /// Determines how far the user needs to refresh preheat window.
    public var preheatRectUpdateRatio: CGFloat = 0.33
    
    private var previousContentOffset = CGPointZero

    /// Initializes the receiver with a given collection view.
    public init(collectionView: UICollectionView) {
        assert(collectionView.collectionViewLayout is UICollectionViewFlowLayout)
        super.init(scrollView: collectionView)
    }

    /// Default value is false. See superclass for more info.
    public override var enabled: Bool {
        didSet {
            if enabled {
                updatePreheatRect()
            } else {
                previousContentOffset = CGPointZero
                updatePreheatIndexPaths([])
            }
        }
    }
    
    public override func scrollViewDidScroll() {
        if enabled {
            updatePreheatRect()
        }
    }

    private func updatePreheatRect() {
        let scrollAxis = collectionViewLayout.scrollDirection
        let updateMargin = (scrollAxis == .Vertical ? CGRectGetHeight : CGRectGetWidth)(collectionView.bounds) * preheatRectUpdateRatio
        let contentOffset = collectionView.contentOffset
        guard distanceBetweenPoints(contentOffset, previousContentOffset) > updateMargin || previousContentOffset == CGPointZero else {
            return
        }
        // Update preheat window
        let scrollDirection: ScrollDirection = ((scrollAxis == .Vertical ? contentOffset.y >= previousContentOffset.y : contentOffset.x >= previousContentOffset.x) || previousContentOffset == CGPointZero) ? .Forward : .Backward
        
        previousContentOffset = contentOffset
        let preheatRect = preheatRectInScrollDirection(scrollDirection)
        let preheatIndexPaths = indexPathsForElementsInRect(preheatRect).subtract(collectionView.indexPathsForVisibleItems())
        updatePreheatIndexPaths(sortIndexPaths(preheatIndexPaths, inScrollDirection: scrollDirection))
    }
    
    private func preheatRectInScrollDirection(direction: ScrollDirection) -> CGRect {
        let viewport = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
        switch collectionViewLayout.scrollDirection {
        case .Vertical:
            let height = CGRectGetHeight(viewport) * preheatRectRatio
            let y = (direction == .Forward) ? CGRectGetMaxY(viewport) : CGRectGetMinY(viewport) - height
            return CGRectIntegral(CGRect(x: 0, y: y, width: CGRectGetWidth(viewport), height: height))
        case .Horizontal:
            let width = CGRectGetWidth(viewport) * preheatRectRatio
            let x = (direction == .Forward) ? CGRectGetMaxX(viewport) : CGRectGetMinX(viewport) - width
            return CGRectIntegral(CGRect(x: x, y: 0, width: width, height: CGRectGetHeight(viewport)))
        }
    }
    
    private func indexPathsForElementsInRect(rect: CGRect) -> Set<NSIndexPath> {
        guard let layoutAttributes = collectionViewLayout.layoutAttributesForElementsInRect(rect) else {
            return []
        }
        return Set(layoutAttributes.filter{ return $0.representedElementCategory == .Cell }.map{ return $0.indexPath })
    }
}
