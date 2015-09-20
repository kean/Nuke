// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

/** Tells the delegate that the preheat window changed significantly.

Added index paths are sorted so that the items closest to the previous preheat window are in the beginning of the array; no matter whether user is scrolling forward of backward.
*/
public protocol ImageCollectionViewPreheatingControllerDelegate: class {
    func collectionViewPreheatingController(controller: ImageCollectionViewPreheatingController, didUpdateWithAddedIndexPaths addedIndexPaths: [NSIndexPath], removedIndexPaths: [NSIndexPath])
}

public class ImageCollectionViewPreheatingController: NSObject {
    public weak var delegate: ImageCollectionViewPreheatingControllerDelegate?
    public let collectionView: UICollectionView
    public internal(set) var preheatIndexPath = Set<NSIndexPath>()
    
    /** The proportion of the collection view bounds (either width or height depending on the scroll direction) that is used as a preheat window. Default value is 2.0.
    */
    public internal(set) var preheatRectRatio = 2.0
    
    /** Determines the offset of the preheat from the center of the collection view visible area.
    
    The value of this property is the ratio of the collection view height for UICollectionViewScrollDirectionVertical and width for UICollectionViewScrollDirectionHorizontal.
    */
    public internal(set) var preheatRectOffset = 0.33
    
    /** Determines how far the user needs to scroll from the point where the current preheat rect was set to refresh it.
    
    The value of this property is the ratio of the collection view height for UICollectionViewScrollDirectionVertical and width for UICollectionViewScrollDirectionHorizontal.
    */
    public internal(set) var preheatRectUpdateRatio = 0.33
    public internal(set) var preheatRect = CGRectZero
    public internal(set) var preheatContentOffset = CGPointZero
    
    deinit {
        self.collectionView.removeObserver(self, forKeyPath: "contentOffset", context: nil)
    }
    
    public init(collectionView: UICollectionView) {
        self.collectionView = collectionView
        super.init()
        self.collectionView.addObserver(self, forKeyPath: "contentOffset", options: [.New], context: nil)
    }
    
    public func resetPreheatRect() {
        self.delegate?.collectionViewPreheatingController(self, didUpdateWithAddedIndexPaths: [], removedIndexPaths: Array(self.preheatIndexPath))
        self.resetPreheatRectIndexPaths()
    }
    
    public func updatePreheatRect() {
        self.resetPreheatRectIndexPaths()
        self.updatePreheatRectIndexPaths()
    }
    
    private func resetPreheatRectIndexPaths() {
        self.preheatIndexPath.removeAll()
        self.preheatRect = CGRectZero
        self.preheatContentOffset = CGPointZero
    }
    
    public override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if object === self.collectionView {
            self.updatePreheatRectIndexPaths()
        } else {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: nil)
        }
    }
    
    private func updatePreheatRectIndexPaths() {
        let layout = self.collectionView.collectionViewLayout as! UICollectionViewFlowLayout
        let isVertical = layout.scrollDirection == .Vertical
        
        let offset = self.collectionView.contentOffset
        let delta = isVertical ? self.preheatContentOffset.y - offset.y : self.preheatContentOffset.x - offset.x
        let margin = isVertical ? Double(CGRectGetHeight(self.collectionView.bounds)) * self.preheatRectUpdateRatio : Double(CGRectGetWidth(self.collectionView.bounds)) * self.preheatRectUpdateRatio
        
        if fabs(Double(delta)) > margin || CGPointEqualToPoint(self.preheatContentOffset, CGPointZero) {
            let isScrollingForward = (isVertical ? offset.y >= self.preheatContentOffset.y : offset.x >= self.preheatContentOffset.x) || CGPointEqualToPoint(self.preheatContentOffset, CGPointZero)
            
            self.preheatContentOffset = offset
            
            let preheatRect = self.preheatRectForScrollingForward(isScrollingForward)
            
            let newIndexPaths = Set(self.indexPathsForElementsInRect(preheatRect))
            let oldIndexPaths = Set(self.preheatIndexPath)
            
            var addedIndexPaths = Set(newIndexPaths)
            addedIndexPaths = addedIndexPaths.subtract(oldIndexPaths)
            
            var removedIndexPaths = Set(oldIndexPaths)
            removedIndexPaths = removedIndexPaths.subtract(newIndexPaths)
            
            self.preheatIndexPath = newIndexPaths
            
            let sortedAddedIndexPath = Array(addedIndexPaths).sort {
                if isScrollingForward {
                    return $0.section < $1.section || $0.item < $1.item
                } else {
                    return $0.section > $1.section || $0.item > $1.item
                }
            }
            
            self.preheatRect = preheatRect
            
            self.delegate?.collectionViewPreheatingController(self, didUpdateWithAddedIndexPaths: sortedAddedIndexPath, removedIndexPaths: Array(removedIndexPaths))
        }
    }
    
    private func preheatRectForScrollingForward(forward: Bool) -> CGRect {
        let layout = self.collectionView.collectionViewLayout as! UICollectionViewFlowLayout
        let isVertical = layout.scrollDirection == .Vertical
        
        // UIScrollView bounds works differently from UIView bounds. It adds the contentOffset to the rect.
        let viewport = self.collectionView.bounds
        var preheatRect: CGRect!
        if isVertical {
            let inset = viewport.size.height - viewport.size.height * CGFloat(self.preheatRectRatio)
            preheatRect = CGRectInset(viewport, 0.0, inset / 2.0)
            let offset = CGFloat(self.preheatRectOffset) * CGRectGetHeight(self.collectionView.bounds)
            preheatRect = CGRectOffset(preheatRect, 0.0, forward ? offset : -offset)
        } else {
            let inset = viewport.size.width - viewport.size.width * CGFloat(self.preheatRectRatio)
            preheatRect = CGRectInset(viewport, inset / 2.0, 0.0)
            let offset = CGFloat(self.preheatRectOffset) * CGRectGetWidth(self.collectionView.bounds)
            preheatRect = CGRectOffset(preheatRect, forward ? offset : -offset, 0.0)
        }
        return CGRectIntegral(preheatRect)
    }
    
    private func indexPathsForElementsInRect(rect: CGRect) -> [NSIndexPath] {
        guard let layoutAttributes = self.collectionView.collectionViewLayout.layoutAttributesForElementsInRect(rect) else {
            return []
        }
        return layoutAttributes.filter{ return $0.representedElementCategory == .Cell }.map{ return $0.indexPath }
    }
}
