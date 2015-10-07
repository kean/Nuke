// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

public class ImagePreheatingControllerForCollectionView: ImagePreheatingController {
    public let collectionView: UICollectionView
    
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
    
    public init(collectionView: UICollectionView) {
        self.collectionView = collectionView
        super.init(scrollView: collectionView)
    }
    
    public override func reset() {
        super.reset()
        self.resetPreheatRect()
    }
    
    public override func update() {
        super.update()
        self.resetPreheatRect()
        self.updatePreheatRect()
    }
    
    internal override func scrollViewDidScroll() {
        self.updatePreheatRect()
    }
    
    private func resetPreheatRect() {
        self.preheatRect = CGRectZero
        self.preheatContentOffset = CGPointZero
    }
    
    private func updatePreheatRect() {
        let layout = self.collectionView.collectionViewLayout as! UICollectionViewFlowLayout
        let isVertical = layout.scrollDirection == .Vertical
        
        let offset = self.collectionView.contentOffset
        let delta = isVertical ? self.preheatContentOffset.y - offset.y : self.preheatContentOffset.x - offset.x
        let margin = isVertical ? Double(CGRectGetHeight(self.collectionView.bounds)) * self.preheatRectUpdateRatio : Double(CGRectGetWidth(self.collectionView.bounds)) * self.preheatRectUpdateRatio
        
        if fabs(Double(delta)) > margin || CGPointEqualToPoint(self.preheatContentOffset, CGPointZero) {
            let isScrollingForward = (isVertical ? offset.y >= self.preheatContentOffset.y : offset.x >= self.preheatContentOffset.x) || CGPointEqualToPoint(self.preheatContentOffset, CGPointZero)
            
            self.preheatContentOffset = offset
            
            self.preheatRect = self.preheatRectForScrollingForward(isScrollingForward)
            let newIndexPaths = Set(self.indexPathsForElementsInRect(self.preheatRect))
            self.updatePreheatIndexPaths(newIndexPaths, scrollingForward: isScrollingForward)
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
