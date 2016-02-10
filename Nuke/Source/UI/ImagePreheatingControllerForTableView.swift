// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import UIKit

public class ImagePreheatingControllerForTableView: ImagePreheatingController {
    public var tableView: UITableView {
        return self.scrollView as! UITableView
    }

    /** The proportion of the collection view size (either width or height depending on the scroll axis) used as a preheat window.
     */
    public var preheatRectRatio: CGFloat = 1.0

    /** Determines how far the user needs to refresh preheat window.
     */
    public var preheatRectUpdateRatio: CGFloat = 0.33

    private var previousContentOffset = CGPointZero

    public init(tableView: UITableView) {
        super.init(scrollView: tableView)
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
        let updateMargin = CGRectGetHeight(self.tableView.bounds) * self.preheatRectUpdateRatio
        let contentOffset = self.tableView.contentOffset
        guard distanceBetweenPoints(contentOffset, self.previousContentOffset) > updateMargin || self.previousContentOffset == CGPointZero else {
            return
        }
        let scrollDirection: ScrollDirection = (contentOffset.y >= self.previousContentOffset.y || self.previousContentOffset == CGPointZero) ? .Forward : .Backward

        self.previousContentOffset = contentOffset
        let preheatRect = self.preheatRectInScrollDirection(scrollDirection)
        let preheatIndexPaths = Set(self.tableView.indexPathsForRowsInRect(preheatRect) ?? []).subtract(self.tableView.indexPathsForVisibleRows ?? [])
        self.updatePreheatIndexPaths(sortIndexPaths(preheatIndexPaths, inScrollDirection: scrollDirection))
    }

    private func preheatRectInScrollDirection(direction: ScrollDirection) -> CGRect {
        let viewport = CGRect(origin: self.tableView.contentOffset, size: self.tableView.bounds.size)
        let height = CGRectGetHeight(viewport) * self.preheatRectRatio
        let y = (direction == .Forward) ? CGRectGetMaxY(viewport) : CGRectGetMinY(viewport) - height
        return CGRectIntegral(CGRect(x: 0, y: y, width: CGRectGetWidth(viewport), height: height))
    }
}
